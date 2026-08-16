/* compatibility.dll - the Compatibility shim for the Ascension 3.3.5a client. v9.
 *
 * PURPOSE
 *   Registers the Lua global `Compatibility` so an (untrusted) rotation addon can
 *   run scripts under a trusted owner name, which unlocks the
 *   classifier-gated action APIs (CastSpellByID, UseAction,
 *   JumpOrAscendStart, ...). The owner name is DERIVED at runtime from the
 *   live trust manifest (ExtendedAnticheatMgr, Extensions.dll) - preferring
 *   AscensionUI (the always-loaded Ascension-owned core UI), then a stock
 *   "Blizzard_*" name, then any trusted name; a manifest with no trusted name fails cleanly
 *   instead of silently blocking. Frames created inside a Compatibility script
 *   inherit the trusted owner, so the addon's handlers cast directly for
 *   the rest of the session. Personal accessibility use.
 *
 * MECHANISM (why this shape)
 *   DllMain spawns SetupThread -> finds the game window (GxWindowClassD3d),
 *   VALIDATES the client layout (see validate_layout - the one check that
 *   matters before the next client update), subclasses the window, posts
 *   WM_APP+1. The subclass runs on the game's window thread - the main
 *   thread, where Lua is idle between messages - which is the only safe
 *   place to touch the FrameScript state. There it:
 *     1. derives the trusted owner from the manifest (once; failure =
 *        permanent, loud, no registration - the addon's issecure probe
 *        then reports the problem to the user)
 *     2. registers Compatibility -> Compatibility_cb via FUN_00817f90 (the game's OWN
 *        API-registration primitive - the stock UI registers its C APIs
 *        the same way; unhooked by the AC)
 *     3. self-tests SILENTLY (result to compatibility.log only) - verifies the
 *        (ok, err) return plumbing
 *     4. arms a 1s keepalive timer (see keepalive_tick)
 *
 *   Compatibility(script): reads arg 1 via FUN_0084e0e0 (lua_tolstring, the
 *   game's own reader), escapes it into a Lua string literal, and runs a
 *   pcall wrapper through FUN_00819210(script, OWNER, OWNER) - the
 *   classifier reads the owner for the duration -> allow path. The wrapper
 *   stashes (ok, value, error) in the globals Compatibility_Ok/Compatibility_Val/
 *   Compatibility_Err; Compatibility then pushes all three back to the Lua caller and
 *   returns 3, so `local ok, value, err = Compatibility("...")` reports a broken
 *   handler instead of failing silently AND hands back the script's first
 *   return value (needed for secure functions that return data). The Lua
 *   return-value path is stock: the game's C-call wrapper reads the
 *   callback's EAX as the result count and FUN_00856010 copies that many
 *   16-byte slots to the caller, bottom-up (first pushed = first result).
 *
 * CALLBACK DESCRIPTOR CONSTRAINT (do not "improve")
 *   The game's C-call wrapper FUN_00856550 reads the REGISTERED CALLBACK'S
 *   CODE BYTES as embedded per-function metadata: entry+0x10 (dword, the
 *   owner held for the callback's duration) and entry+0x4d/+0x4e/+0x4f
 *   (min args / flag / max args, consumed by FUN_00855de0), and
 *   FUN_0086b5a0 validates the callback pointer against loaded-module
 *   executable memory. A hand-written blob or anonymous copy carries wrong
 *   descriptor bytes and crashes the arg machinery (v5-v7).
 *   A plain -O2 function's bytes at +0x4d..0x4f are compiler accidents, so
 *   Compatibility_cb is a NAKED STUB that pins them: dead bytes at +0x4d..0x4f
 *   read flag=0x01 (the FUN_00855de0 vararg path - identical to the
 *   validated v8) and max=0x00 (no extra frame growth). Verify after every
 *   rebuild: objdump and confirm entry+0x4d/0x4e/0x4f == b3 01 00.
 *   Consequence: the module cannot be unloaded while Compatibility lives.
 *
 * LAYOUT VALIDATION (why the byte table)
 *   The five original targets plus the four Lua APIs are hardcoded; the
 *   client has no ASLR and the addresses are stable TODAY, but any client
 *   patch that shifts code turns the first call into a jump into arbitrary
 *   code in-process. SetupThread therefore compares the first 16 bytes of
 *   each target against snapshots taken from the current client before it
 *   subclasses or registers anything. Mismatch -> log + abort; never
 *   register. FUN_00819210 is hooked by Extensions (a pass-through): a
 *   5-byte E9 detour to 0x794ada60 with INT3 padding after it (hook-engine
 *   owned), so for it the check is the displacement (must land in
 *   Extensions' live range) and nothing else; unhooked targets are
 *   compared byte-for-byte. Rebuild the table when a client update lands.
 *
 * No hooks of our own, no .text patches, no global unlock state. Logs to
 * compatibility.log next to the DLL (ASCII only - the log and console cannot
 * render non-ASCII). fs=00000000 on DllMain-era lines is EXPECTED (the game has
 * not created the FrameScript state yet) - not evidence of anything wrong.
 */
#include <windows.h>
#include <string.h>

/* ------------------------------------------------------------------ *
 * Game addresses. Stable because Ascension.exe has NO ASLR.
 * ------------------------------------------------------------------ */
#define REGISTER_GLOBAL  0x00817f90   /* FUN_00817f90(name, cb): the game's Lua API registration (unhooked) */
#define READ_STRING_ARG  0x0084e0e0   /* lua_tolstring(state, idx, &len) -> const char* (unhooked) */
#define SECURE_EXEC      0x00819210   /* FUN_00819210(script, name, owner): the secure executor */
#define FS_STATE         0x00d3f78c   /* global FrameScript state pointer (lua_State*) */
#define OWNER_KEY        0x00d4139c   /* the classifier's owner lookup key (set during secure exec) */
#define LUA_GETFIELD     0x0084e590   /* lua_getfield(state, idx, key): pushes the field value */
#define LUA_TYPE         0x0084deb0   /* lua_type(state, idx): tt, -1 for invalid index */
#define LUA_REMOVE       0x0084dc50   /* lua_remove(state, idx): pop (-1) and stack shifts */
#define LUA_TOBOOLEAN    0x0084e0b0   /* lua_toboolean(state, idx) */
/* The ExtendedAnticheatMgr singleton address is NOT hardcoded here: Ascension
 * rebuilds Extensions.dll and its .data layout shifts (the 2026-08-13 build
 * moved the singleton ~12KB). find_ac_singleton() below locates it by SHAPE at
 * runtime; g_ac_singleton holds the result (0 = failed). */

#define LUA_GLOBALSINDEX (-10002)
#define LUA_TNIL         0
#define LUA_TFUNCTION    6

/* Log path is derived from the DLL's own location at load - see init_logpath. */
#define WM_COMPATIBILITY        (WM_APP + 1)   /* posted to the game window by SetupThread */
#define COMPATIBILITY_TIMER_ID  0x4A4A         /* keepalive window timer id (high, no collision) */
#define COMPATIBILITY_TIMER_MS  1000           /* 1s: reload recovery latency = one tick */

/* Named limits used across the manifest scan and the callback. */
#define MAX_TRUSTED_NAME_LEN 63         /* longest trusted addon name (buffer = +1) */
#define SSO_INLINE_MAX       15         /* std::string SSO inline threshold */
#define BLIZZARD_PREFIX_LEN  9          /* strlen("Blizzard_") */
#define MIN_HEAP_ADDR        0x10000    /* names and the vector live above this */
#define MAX_SCRIPT_LEN       0x100000   /* escape-buffer sanity cap */
#define EXT_BASE             0x79310000 /* Extensions.dll live range start */
#define EXT_END              0x7a080000 /* Extensions.dll live range end */

/* Client layout snapshots, 16 bytes each, taken from the current
 * ascension-live/Ascension.exe. Rebuild when the client updates. */
static const unsigned char EXP_REGISTER[16]   = {0x55,0x8b,0xec,0x8b,0x45,0x0c,0x56,0x8b,0x35,0x8c,0xf7,0xd3,0x00,0x6a,0x00,0x50};
static const unsigned char EXP_READ_STR[16]   = {0x55,0x8b,0xec,0x56,0x8b,0x75,0x08,0x57,0x8b,0x7d,0x0c,0x8b,0xc7,0x8b,0xce,0xe8};
static const unsigned char EXP_GETFIELD[16]   = {0x55,0x8b,0xec,0x83,0xec,0x10,0x8b,0x45,0x0c,0x53,0x56,0x8b,0x75,0x08,0x57,0x8b};
static const unsigned char EXP_LUATYPE[16]    = {0x55,0x8b,0xec,0x8b,0x45,0x0c,0x8b,0x4d,0x08,0xe8,0x02,0xfb,0xff,0xff,0x3d,0x78};
static const unsigned char EXP_LUAREMOVE[16]  = {0x55,0x8b,0xec,0x8b,0x45,0x0c,0x56,0x8b,0x75,0x08,0x8b,0xce,0xe8,0x5f,0xfd,0xff};
static const unsigned char EXP_TOBOOLEAN[16]  = {0x55,0x8b,0xec,0x8b,0x45,0x0c,0x8b,0x4d,0x08,0xe8,0x02,0xf9,0xff,0xff,0x8b,0x48};
static const unsigned char EXP_SECEXEC[16]    = {0x55,0x8b,0xec,0x51,0x83,0x05,0xa0,0x13,0xd4,0x00,0x01,0xa1,0x9c,0x13,0xd4,0x00};

typedef void  (__cdecl *Register_t)(const char*, void*);
typedef const char* (__cdecl *ReadStr_t)(unsigned int, int, unsigned int*);
typedef void  (__cdecl *SecExec_t)(const char*, const char*, const char*);
typedef void  (__cdecl *GetField_t)(unsigned int, int, const char*);
typedef int   (__cdecl *Type_t)(unsigned int, int);
typedef void  (__cdecl *Remove_t)(unsigned int, int);
typedef int   (__cdecl *ToBool_t)(unsigned int, int);

/* g_registered: 1 after the first registration (WM_COMPATIBILITY arrives once).
 * g_last_fs: the FrameScript state pointer at the last time we touched the
 *   state - used ONLY as a don't-touch-during-reload guard (see
 *   keepalive_tick); the re-register DECISION is the resolution check.
 * g_owner / g_owner_name: the manifest-derived trusted owner ("" = failed).
 * g_oldProc: the game's original window proc - all non-Compatibility messages
 *   pass through untouched. The subclass is NEVER restored - the keepalive
 *   timer needs it. */
static int g_registered = 0;
static unsigned long g_last_fs = 0;
static char g_owner[MAX_TRUSTED_NAME_LEN + 1];
static const char* g_owner_name = NULL;
static WNDPROC g_oldProc = NULL;
static HMODULE g_hModule = NULL;  /* our own module, for FreeLibraryAndExitThread on fatal error */
static int g_waiting_logged = 0;  /* one-shot "waiting for manifest" log */

/* ---------- logging ---------- */

static char g_logpath[MAX_PATH];

/* The log lives next to the DLL (the injector drops compatibility.dll beside
 * compatibility.exe), so derive the path from the DLL's own location instead of
 * hardcoding C:\local. Runs once at DllMain, before the first logmsg. */
static void init_logpath(HMODULE self) {
    static const char LOGNAME[] = "compatibility.log";
    DWORD n = GetModuleFileNameA(self, g_logpath, MAX_PATH);
    if (n >= MAX_PATH) n = MAX_PATH - 1;   /* truncated: stay inside the buffer */
    char* slash = NULL;
    DWORD i;
    for (i = 0; i < n; i++) {
        if (g_logpath[i] == '\\' || g_logpath[i] == '/') slash = g_logpath + i;
    }
    if (slash) memcpy(slash + 1, LOGNAME, sizeof(LOGNAME));
    else memcpy(g_logpath, LOGNAME, sizeof(LOGNAME));
}

/* Append a buffer to the log file - the one place the file is opened, written
 * and closed. logmsgf builds the buffer (logmsg delegates to it); this does the I/O. */
static void log_write(const char* buf, int len) {
    HANDLE h = CreateFileA(g_logpath, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    DWORD n;
    WriteFile(h, buf, (DWORD)len, &n, NULL);
    CloseHandle(h);
}

/* Append a printf-formatted line to the log: "[HH:MM:SS.mmm] [tid] <msg>
 * (fs=STATE)". Timestamp is local wall-clock (GetLocalTime); tid is the writing
 * thread; fs is the FrameScript state pointer - the value that proves which Lua
 * state a step ran against (and the /reload change). DllMain-era lines show
 * fs=00000000, the expected "state not created yet", not evidence of a fault.
 * Uses wvsprintfA (the user32 varargs variant - the CRT's vsnprintf is not
 * linked here). */
static void logmsgf(const char* fmt, ...) {
    SYSTEMTIME st;
    va_list ap;
    char buf[512];
    int len;
    GetLocalTime(&st);
    len = wsprintfA(buf, "[%02u:%02u:%02u.%03u] [%lu] ",
                    st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
                    (unsigned long)GetCurrentThreadId());
    va_start(ap, fmt);
    len += wvsprintfA(buf + len, fmt, ap);
    va_end(ap);
    len += wsprintfA(buf + len, " (fs=%08lx)\r\n", *(volatile unsigned long*)FS_STATE);
    log_write(buf, len);
}

/* Append a fixed string: logmsgf("%s", s). */
static void logmsg(const char* s) {
    logmsgf("%s", s);
}

/* Fatal error BEFORE anything is installed (no subclass yet): log, then unload
 * the DLL and exit the setup thread. FreeLibraryAndExitThread drops the
 * LoadLibrary refcount and exits atomically, leaving the game process clean so
 * the user can re-inject (LoadLibrary re-runs DllMain) without a restart. Only
 * safe pre-subclass - once SubclassProc is installed the DLL must stay resident. */
static void __attribute__((noreturn)) fatal_exit(const char* msg) {
    logmsg(msg);
    FreeLibraryAndExitThread(g_hModule, 1);
}


/* ---------- runtime AC singleton resolution ---------- */

/* The ExtendedAnticheatMgr singleton lives in Extensions.dll, which Ascension
 * rebuilds (2026-08-13 moved it from 0x79ef603c). Its address is found by
 * SHAPE, not by hardcoded address: scan Extensions.dll's writable sections for
 *   [ vftable-in-image ][ heap begin ][ heap end ]
 * where (end-begin) is a whole number of 0x1c-byte manifest entries and the
 * first entry decodes to a printable addon name with a 0/1 flag. That shape is
 * stable across rebuilds (std::string SSO + uint32 flag, and the singleton's
 * member order). Returns the singleton address, or 0 on failure. */
#define AC_ENTRY_LEN   0x1c   /* {std::string name (MSVC SSO, 0x18 bytes), uint32 flag} */
#define AC_ENTRY_SSIZE 0x10   /* std::string::_Mysize */
#define AC_ENTRY_FLAG  0x18   /* flag: 1 = trusted */
#define AC_MAX_ENTRIES 400    /* observed 237, capacity 316; bound the walk */

static unsigned long g_ac_singleton = 0;

static int valid_ac_entry(unsigned long e) {
    unsigned int size, flag, i;
    const char* name;
    if (IsBadReadPtr((void*)e, AC_ENTRY_LEN)) return 0;
    size = *(unsigned int*)(e + AC_ENTRY_SSIZE);
    flag = *(unsigned int*)(e + AC_ENTRY_FLAG);
    if (size > MAX_TRUSTED_NAME_LEN || flag > 1) return 0;
    name = (size <= SSO_INLINE_MAX) ? (const char*)e : *(const char**)e;   /* SSO inline vs heap */
    if ((unsigned long)name < MIN_HEAP_ADDR || IsBadStringPtrA(name, (UINT_PTR)size + 1)) return 0;
    for (i = 0; i < size; i++) {
        unsigned char c = (unsigned char)name[i];
        if (c < 0x20 || c > 0x7e) return 0;
    }
    return 1;
}

static unsigned long find_ac_singleton(void) {
    HMODULE ext = GetModuleHandleA("Extensions.dll");
    IMAGE_DOS_HEADER* dos;
    IMAGE_NT_HEADERS* nt;
    IMAGE_SECTION_HEADER* sec;
    unsigned long base, size, i;
    if (!ext) { logmsg("ac: Extensions.dll not found"); return 0; }
    dos = (IMAGE_DOS_HEADER*)ext;
    if (IsBadReadPtr(dos, sizeof(*dos)) || dos->e_magic != IMAGE_DOS_SIGNATURE) {
        logmsg("ac: bad DOS header"); return 0;
    }
    nt = (IMAGE_NT_HEADERS*)((unsigned char*)ext + dos->e_lfanew);
    if (IsBadReadPtr(nt, sizeof(*nt)) || nt->Signature != IMAGE_NT_SIGNATURE) {
        logmsg("ac: bad NT header"); return 0;
    }
    base = (unsigned long)ext;
    size = nt->OptionalHeader.SizeOfImage;
    sec = IMAGE_FIRST_SECTION(nt);
    for (i = 0; i < nt->FileHeader.NumberOfSections; i++, sec++) {
        unsigned long start, ssize, end, addr, vft, begin, vend, n;
        if (!(sec->Characteristics & IMAGE_SCN_MEM_WRITE)) continue;  /* singleton is in a writable section */
        start = base + sec->VirtualAddress;
        ssize = sec->Misc.VirtualSize ? sec->Misc.VirtualSize : sec->SizeOfRawData;
        if (start + ssize > base + size) ssize = base + size - start;
        for (addr = start; addr + 12 <= start + ssize; addr += 4) {
            vft = *(unsigned long*)addr;
            begin = *(unsigned long*)(addr + 4);
            vend = *(unsigned long*)(addr + 8);
            if (!(vft >= base && vft < base + size)) continue;          /* vftable: inside Extensions.dll */
            if (!(begin > MIN_HEAP_ADDR && (begin < base || begin >= base + size))) continue;  /* vector: on heap */
            if (vend <= begin) continue;
            n = vend - begin;
            if (n % AC_ENTRY_LEN || n / AC_ENTRY_LEN < 1 || n / AC_ENTRY_LEN > AC_MAX_ENTRIES) continue;
            if (!valid_ac_entry(begin)) continue;
            logmsgf("ac: singleton resolved at %08lx (vftable %08lx, %u entries)",
                    addr, vft, (unsigned)(n / AC_ENTRY_LEN));
            return addr;
        }
    }
    return 0;
}

/* ---------- layout validation ---------- */

/* Compare the live bytes of every hardcoded code target against the
 * snapshots; verify the AC singleton's vtable dword. SECURE_EXEC is
 * HOOKED by Extensions (a pass-through): the live dump shows a 5-byte E9
 * detour to 0x794ada60 with the next six bytes INT3 padding (hook-engine
 * owned) before the original body resumes - so for a hooked function the
 * check is the displacement (must land in Extensions' live range) and
 * NOTHING ELSE; the post-detour bytes are not ours to compare. An
 * unhooked function must match the full 16-byte snapshot. Any mismatch -
 * or an E9 that no longer points into Extensions - -> log and return 0;
 * SetupThread then aborts before subclassing, so a patched client can
 * never turn the first call into a jump into arbitrary code. Runs once at
 * injection, on the setup thread. */
static int validate_layout(void) {
    struct { unsigned long va; const unsigned char* exp; const char* name; } checks[] = {
        { REGISTER_GLOBAL, EXP_REGISTER,   "FUN_00817f90" },
        { READ_STRING_ARG, EXP_READ_STR,   "lua_tolstring" },
        { LUA_GETFIELD,    EXP_GETFIELD,   "lua_getfield" },
        { LUA_TYPE,        EXP_LUATYPE,    "lua_type" },
        { LUA_REMOVE,      EXP_LUAREMOVE,  "lua_remove" },
        { LUA_TOBOOLEAN,   EXP_TOBOOLEAN,  "lua_toboolean" },
    };
    unsigned char b[16];
    int ok = 1, i;
    for (i = 0; i < (int)(sizeof(checks) / sizeof(checks[0])); i++) {
        if (IsBadReadPtr((void*)checks[i].va, 16)) {
            logmsgf("layout: %s unreadable", checks[i].name); ok = 0; continue;
        }
        memcpy(b, (void*)checks[i].va, 16);
        if (memcmp(b, checks[i].exp, 16) != 0) {
            logmsgf("layout: %s mismatch (%02x %02x %02x %02x... != %02x %02x %02x %02x...)",
                    checks[i].name, b[0], b[1], b[2], b[3],
                    checks[i].exp[0], checks[i].exp[1], checks[i].exp[2], checks[i].exp[3]);
            ok = 0;
        }
    }
    if (IsBadReadPtr((void*)SECURE_EXEC, 16)) {
        logmsg("layout: FUN_00819210 unreadable"); ok = 0;
    } else {
        memcpy(b, (void*)SECURE_EXEC, 16);
        if (b[0] == 0xE9) {                       /* hooked by Extensions (pass-through) */
            unsigned long tgt = SECURE_EXEC + 5 + (unsigned long)*(long*)(b + 1);
            if (tgt < EXT_BASE || tgt > EXT_END) {
                logmsgf("layout: FUN_00819210 hook target out of Extensions range (%08lx)", tgt);
                ok = 0;
            }
            /* post-detour bytes are hook-engine owned (INT3 padding etc.) -
             * the displacement is the whole check. */
        } else if (memcmp(b, EXP_SECEXEC, 16) != 0) {
            logmsg("layout: FUN_00819210 prologue/body mismatch"); ok = 0;
        }
    }
    if (!ok)
        logmsg("layout: REFUSING - client layout changed; rebuild with new snapshots");
    return ok;
}

/* ---------- manifest-derived trusted owner ---------- */


/* Walk the live trust manifest (the vector at singleton+4) and pick the
 * best trusted (flag=1) name. Preference order: AscensionUI (the always-
 * loaded Ascension-owned core UI, present on every server), then a stock
 * "Blizzard_*" (the always-loaded set), then any trusted name. Rationale:
 * the owner must be an addon the server believes is legitimately RUNNING on
 * this account/server - a disabled or mode-specific addon would be a
 * trivially-checkable lie. Every read is
 * bounded (entry count cap, IsBadReadPtr/IsBadStringPtrA, name length cap).
 * Failure -> "" : a manifest that dropped every trusted entry (or a changed
 * layout) becomes a LOUD clean failure - no registration, the addon's
 * issecure probe reports it - instead of a mystery block. Runs once, on the
 * window thread, at first registration. */
static const char* choose_owner(void) {
    unsigned char* begin = *(unsigned char**)(g_ac_singleton + 4);
    unsigned char* end = *(unsigned char**)(g_ac_singleton + 8);
    const char* first = NULL;              /* first trusted name (last resort) */
    unsigned int first_size = 0;
    const char* blizz = NULL;              /* first Blizzard_* trusted (fallback) */
    unsigned int blizz_size = 0;
    unsigned int count, i;
    if (!begin || !end || end < begin) { logmsg("owner: manifest vector invalid"); return ""; }
    count = (unsigned int)(end - begin) / AC_ENTRY_LEN;
    if (count == 0 || count > AC_MAX_ENTRIES) {
        logmsgf("owner: manifest count %u implausible", count); return "";
    }
    for (i = 0; i < count; i++) {
        unsigned char* e = begin + (size_t)i * AC_ENTRY_LEN;
        unsigned int size, flag;
        const char* name;
        if (IsBadReadPtr(e, AC_ENTRY_LEN)) break;
        size = *(unsigned int*)(e + AC_ENTRY_SSIZE);
        if (size > MAX_TRUSTED_NAME_LEN) continue;                       /* sanity: no trusted name is longer */
        name = (size <= SSO_INLINE_MAX) ? (const char*)e : *(const char**)e;   /* MSVC SSO: inline vs heap */
        if ((size_t)name < MIN_HEAP_ADDR || IsBadStringPtrA(name, MAX_TRUSTED_NAME_LEN + 1)) continue;
        flag = *(unsigned int*)(e + AC_ENTRY_FLAG);
        if (flag != 1) continue;
        if (!first) { first = name; first_size = size; }
        if (strcmp(name, "AscensionUI") == 0) {        /* best: always-loaded Ascension core */
            size = size < MAX_TRUSTED_NAME_LEN ? size : MAX_TRUSTED_NAME_LEN;
            memcpy(g_owner, name, size); g_owner[size] = 0;
            logmsgf("owner: derived from manifest: %s (entry %u/%u)", g_owner, i, count);
            return g_owner;
        }
        if (!blizz && strncmp(name, "Blizzard_", BLIZZARD_PREFIX_LEN) == 0) {  /* fallback: always-loaded stock */
            blizz = name; blizz_size = size;
        }
    }
    if (blizz) {
        blizz_size = blizz_size < MAX_TRUSTED_NAME_LEN ? blizz_size : MAX_TRUSTED_NAME_LEN;
        memcpy(g_owner, blizz, blizz_size); g_owner[blizz_size] = 0;
        logmsgf("owner: derived from manifest: %s (no AscensionUI)", g_owner);
        return g_owner;
    }
    if (first) {
        first_size = first_size < MAX_TRUSTED_NAME_LEN ? first_size : MAX_TRUSTED_NAME_LEN;
        memcpy(g_owner, first, first_size); g_owner[first_size] = 0;
        logmsgf("owner: derived from manifest: %s (no AscensionUI/Blizzard_* trusted)", g_owner);
        return g_owner;
    }
    logmsg("owner: NO trusted name in manifest");
    return "";
}

/* ---------- the Compatibility Lua global ---------- */

/* The pcall wrapper the user script is embedded into. The script is escaped
 * into a Lua string literal, so loadstring compiles it; pcall runs it; the
 * (ok, err) pair is stashed in the globals Compatibility_Ok / Compatibility_Err for
 * Compatibility_body to push back. This wrapper itself can never throw (only
 * assignments + loadstring + pcall), so FUN_00819210 never sees an error. */
static const char WRAP_PRE[]  = "local f,e=loadstring(\"";
static const char WRAP_POST[] = "\");local ok,val,err;if f then ok,val,err=pcall(f);if ok then err=nil else err=val;val=nil end else ok=false;err=e end;Compatibility_Ok=ok;Compatibility_Err=err;Compatibility_Val=val";
static const char FAIL_NOSCRIPT[] = "Compatibility_Ok=false;Compatibility_Err=\"Compatibility: no script argument\";Compatibility_Val=nil";
static const char FAIL_NUL[]      = "Compatibility_Ok=false;Compatibility_Err=\"Compatibility: script contains a NUL byte\";Compatibility_Val=nil";
static const char FAIL_ALLOC[]    = "Compatibility_Ok=false;Compatibility_Err=\"Compatibility: out of memory\";Compatibility_Val=nil";

/* Escape arbitrary script bytes into a Lua string literal: backslash and
 * double-quote are backslash-escaped, \n \r \t become escapes, and every
 * other control or 8-bit byte becomes a 3-digit decimal escape (\ddd -
 * always three digits so a following digit can never merge into it). A NUL
 * byte cannot appear in a Lua literal: returns NULL. Heap buffer, caller
 * frees. */
static char* escape_literal(const char* s, unsigned int len) {
    char* buf = (char*)HeapAlloc(GetProcessHeap(), 0, (size_t)len * 4 + 1);
    char* p = buf;
    unsigned int i;
    if (!buf) return NULL;
    for (i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
        case '\\': *p++ = '\\'; *p++ = '\\'; break;
        case '"':  *p++ = '\\'; *p++ = '"';  break;
        case '\n': *p++ = '\\'; *p++ = 'n';  break;
        case '\r': *p++ = '\\'; *p++ = 'r';  break;
        case '\t': *p++ = '\\'; *p++ = 't';  break;
        case 0:    HeapFree(GetProcessHeap(), 0, buf); return NULL;
        default:
            if (c < 0x20 || c >= 0x80) {
                *p++ = '\\';
                *p++ = (char)('0' + c / 100);
                *p++ = (char)('0' + (c / 10) % 10);
                *p++ = (char)('0' + c % 10);
            } else {
                *p++ = (char)c;
            }
        }
    }
    *p = 0;
    return buf;
}

/* Push the stashed (ok, value, error) onto the Lua stack as three values.
 * Lua's poscall reads results BOTTOM-UP from the results block: the FIRST
 * value pushed is the FIRST result the caller sees (FUN_00856010 copies
 * src forward starting at top - n, exactly like stock luaD_poscall). So
 * push ok, then value, then err, and the caller receives the
 * pcall-idiomatic triple (ok, value, err) - the same shape as
 * `local ok, val, err = pcall(f)`. Compatibility_body then returns 3 and the
 * game's wrapper copies all three. */
static void push_result(unsigned int state) {
    GetField_t gf = (GetField_t)LUA_GETFIELD;
    gf(state, LUA_GLOBALSINDEX, "Compatibility_Ok");
    gf(state, LUA_GLOBALSINDEX, "Compatibility_Val");
    gf(state, LUA_GLOBALSINDEX, "Compatibility_Err");
}

/* The real implementation behind Compatibility_cb (see the naked stub below for
 * why there are two). Runs on whatever thread Lua called Compatibility from.
 *   1. read the script (arg 1) with the game's own reader, copy-safety via
 *      escaping (the nested exec can trigger a Lua GC that moves/frees the
 *      arg's TString, so the arg pointer must not survive the exec)
 *   2. run the pcall wrapper through FUN_00819210(OWNER, OWNER) - the
 *      classifier reads the trusted owner for the duration, so protected
 *      calls inside the script pass; the wrapper's pcall contains errors
 *      so nothing can throw out of the exec
 *   3. push (ok, value, err) and return 3 - a broken script now surfaces
 *      as `local ok, value, err = Compatibility("...")` instead of a silent
 *      no-op, and the script's first return value comes back (secure
 *      functions that return data are readable this way). */
static int __cdecl Compatibility_body(unsigned int state) __asm__("Compatibility_body") __attribute__((used));
static int __cdecl Compatibility_body(unsigned int state) {
    ReadStr_t read_str = (ReadStr_t)READ_STRING_ARG;
    SecExec_t exec = (SecExec_t)SECURE_EXEC;
    unsigned int len = 0;
    const char* script = read_str(state, 1, &len);
    if (!script || len == 0) {
        exec(FAIL_NOSCRIPT, g_owner_name, g_owner_name);
    } else if (len > MAX_SCRIPT_LEN) {                  /* sanity cap on the escape buffer */
        exec(FAIL_ALLOC, g_owner_name, g_owner_name);
    } else {
        char* esc = escape_literal(script, len);
        if (!esc) {
            exec(FAIL_NUL, g_owner_name, g_owner_name);
        } else {
            size_t pre = sizeof(WRAP_PRE) - 1;
            size_t esc_len = strlen(esc);
            size_t post = sizeof(WRAP_POST) - 1;
            char* wrap = (char*)HeapAlloc(GetProcessHeap(), 0, pre + esc_len + post + 1);
            if (!wrap) {
                exec(FAIL_ALLOC, g_owner_name, g_owner_name);
            } else {
                memcpy(wrap, WRAP_PRE, pre);
                memcpy(wrap + pre, esc, esc_len);
                memcpy(wrap + pre + esc_len, WRAP_POST, post + 1);
                exec(wrap, g_owner_name, g_owner_name);
                HeapFree(GetProcessHeap(), 0, wrap);
            }
            HeapFree(GetProcessHeap(), 0, esc);
        }
    }
    push_result(state);
    return 3;
}

/* The REGISTERED callback. The engine reads our code bytes as metadata
 * (see the CALLBACK DESCRIPTOR CONSTRAINT header note), so this is a naked
 * stub that pins the descriptor bytes instead of leaving them to compiler
 * accident: 0x45 NOPs pad entry+0x00..0x44 (entry+0x10 = 0x90909090, the
 * owner dword - as inert as any other code bytes, and never observed by
 * the classifier because Compatibility_body makes no protected calls directly),
 * then `jmp Compatibility_body` at +0x45..0x49, then three dead NOPs, then the
 * dead bytes b3 01 00 at +0x4d..0x4f (min=0xb3, flag=0x01, max=0x00 - the
 * FUN_00855de0 vararg path with no extra frame growth, same as v8). The
 * dead bytes are never executed. The stack is untouched by the stub, so
 * Compatibility_body sees `state` exactly as the engine passed it. */
__attribute__((naked)) static int __cdecl Compatibility_cb(unsigned int state) {
    __asm__ __volatile__(
        ".rept 0x45\n\t.byte 0x90\n\t.endr\n\t"  /* +0x00..0x44: pad */
        "jmp Compatibility_body\n\t"                     /* +0x45..0x49 */
        ".byte 0x90,0x90,0x90\n\t"                /* +0x4a..0x4c: dead */
        ".byte 0xb3,0x01,0x00\n\t"                /* +0x4d..0x4f: min/flag/max (dead) */
    );
}

/* ---------- registration + self-test ---------- */

/* Runs on the game's window thread (via WM_COMPATIBILITY or the keepalive),
 * when Lua is idle. Registers the global, then runs a SILENT self-test: a pcall
 * of a harmless script through Compatibility, whose (ok, err) result goes only
 * to compatibility.log - no chat output ever (a screenshot/stream must not show
 * the shim). The self-test makes NO protected calls: with a wrong owner the
 * classifier's block popup is exactly what we do not want during the injection;
 * trust status is verified separately via /run Compatibility("print(issecure())"). */
static int run_registration(void) {
    Register_t reg = (Register_t)REGISTER_GLOBAL;
    SecExec_t exec = (SecExec_t)SECURE_EXEC;
    unsigned long fs;
    if (!g_ac_singleton) {
        g_ac_singleton = find_ac_singleton();
        if (!g_ac_singleton) {
            if (!g_waiting_logged) {
                logmsg("compatibility: manifest not populated yet - waiting (retrying every 1s)");
                g_waiting_logged = 1;
            }
            return 0;   /* retry next tick */
        }
    }
    if (!g_owner_name) {
        g_owner_name = choose_owner();
        if (!g_owner_name[0]) {
            logmsg("compatibility: NO trusted owner - refusing to register (addon probe will report)");
            return 0;
        }
    }
    fs = *(volatile unsigned long*)FS_STATE;
    if (!fs || IsBadReadPtr((void*)fs, 0x100)) {
        logmsg("compatibility: FrameScript state invalid - not registering");
        return 0;
    }
    reg("Compatibility", (void*)Compatibility_cb);
    g_registered = 1;
    logmsg("compatibility: Compatibility registered");
    exec("local ok,err=pcall(Compatibility,'-- compatibility self-test');Compatibility_Ok=ok;Compatibility_Err=err;Compatibility_Val=nil",
         g_owner_name, g_owner_name);
    fs = *(volatile unsigned long*)FS_STATE;
    if (fs) {
        GetField_t gf = (GetField_t)LUA_GETFIELD;
        ToBool_t tb = (ToBool_t)LUA_TOBOOLEAN;
        Remove_t rm = (Remove_t)LUA_REMOVE;
        gf(fs, LUA_GLOBALSINDEX, "Compatibility_Ok");
        logmsgf("compatibility: self-test ok=%d", tb(fs, -1));
        rm(fs, -1);
    }
    g_last_fs = *(volatile unsigned long*)FS_STATE;
    return 1;
}

/* Does the CURRENT Lua state still resolve Compatibility as a function? This is
 * the condition the keepalive actually cares about: /reload rebuilds the
 * state and wipes every global, including Compatibility, and the state pointer
 * alone cannot tell us that (a rebuilt state can land at the same
 * address). One getfield + one type read + one pop per second - nothing. */
static int compatibility_alive(unsigned int state) {
    GetField_t gf = (GetField_t)LUA_GETFIELD;
    Type_t tp = (Type_t)LUA_TYPE;
    Remove_t rm = (Remove_t)LUA_REMOVE;
    int t;
    gf(state, LUA_GLOBALSINDEX, "Compatibility");
    t = tp(state, -1);
    rm(state, -1);
    return t == LUA_TFUNCTION;
}

/* Keepalive, every 1s on the window thread (WM_TIMER). The re-register
 * DECISION is purely resolution-based: Compatibility gone -> re-register (idempotent)
 * + silent self-test. The state pointer is used only as a safety defer -
 * if it changed since the last tick, a reload is in flight and the state
 * must not be touched until it settles (a freed mid-teardown state would
 * crash getfield; a rebuilt state at a fresh address is exactly what the
 * defer handles). No per-tick logging: a quiet tick writes nothing, so the
 * log only ever records real events. */
static void keepalive_tick(void) {
    unsigned long fs = *(volatile unsigned long*)FS_STATE;
    if (!fs) return;                        /* state not up yet */
    if (fs != g_last_fs) {                  /* reload in flight / just done: settle one tick */
        g_last_fs = fs;
        return;
    }
    if (!g_registered) {                    /* initial registration still pending */
        run_registration();                /* retry: manifest may not be populated yet */
        return;
    }
    if (compatibility_alive(fs)) return;           /* still alive: silent tick */
    logmsg("compatibility: Compatibility global missing - re-registering");
    run_registration();
}

/* The subclassed window proc - the bridge that runs our code on the game's
 * window thread (the main thread; Lua is idle at message boundaries, which
 * is the only safe point to drive the FrameScript machinery). WM_COMPATIBILITY
 * performs the registration (and arms the keepalive only on success);
 * WM_TIMER (our id only) runs the keepalive; everything else passes
 * through to the original proc untouched. The subclass is intentionally
 * never restored - the keepalive needs it for the session. */
static LRESULT CALLBACK SubclassProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_COMPATIBILITY) {
        logmsg("subclass: WM_COMPATIBILITY on window thread");
        if (!g_registered) {
            run_registration();   /* first attempt; timer retries if login */
        } else {
            logmsg("subclass: already registered, skipping");
        }
        /* arm the keepalive regardless: it retries registration until the
         * manifest is populated, then handles /reload recovery. */
        SetTimer(hwnd, COMPATIBILITY_TIMER_ID, COMPATIBILITY_TIMER_MS, NULL);
        logmsg("subclass: keepalive timer set (1s)");
        return 0;
    }
    if (msg == WM_TIMER && wParam == COMPATIBILITY_TIMER_ID) {
        keepalive_tick();
        return 0;
    }
    if (g_oldProc)
        return CallWindowProcA(g_oldProc, hwnd, msg, wParam, lParam);
    return DefWindowProcA(hwnd, msg, wParam, lParam);
}

/* Setup thread spawned from DllMain. Finds the game window ONCE (inject after
 * the game is up), VALIDATES the client layout (aborts cleanly on any mismatch -
 * before subclassing, so nothing is installed), subclasses the window and posts
 * WM_COMPATIBILITY. Exits; the subclass + timer carry the rest - the timer
 * retries registration until the manifest is populated, then handles /reload. */
static DWORD WINAPI SetupThread(LPVOID param) {
    HWND hwnd;
    (void)param;
    logmsg("setup: looking for game window");
    hwnd = FindWindowA("GxWindowClassD3d", NULL);
    if (!hwnd) {
        fatal_exit("setup: game window not found - unload (inject once the game is up)");
    }
    if (!validate_layout()) {
        fatal_exit("setup: layout mismatch - unloading (re-inject a matching build)");
    }
    g_oldProc = (WNDPROC)GetWindowLongPtrA(hwnd, GWLP_WNDPROC);
    SetWindowLongPtrA(hwnd, GWLP_WNDPROC, (LONG_PTR)SubclassProc);
    PostMessageA(hwnd, WM_COMPATIBILITY, 0, 0);
    logmsg("setup: subclassed + posted WM_COMPATIBILITY");
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    (void)lpvReserved;
    if (fdwReason == DLL_PROCESS_ATTACH) {
        HANDLE t;
        g_hModule = hinstDLL;
        init_logpath(hinstDLL);
        DisableThreadLibraryCalls(hinstDLL);
        logmsg("dllmain: compatibility attached");
        t = CreateThread(NULL, 0, SetupThread, NULL, 0, NULL);
        if (t) CloseHandle(t);
    }
    /* DLL_PROCESS_DETACH: nothing to clean up - the subclass and timer die
     * with the process (the DLL is never unloaded mid-session; see the
     * CALLBACK DESCRIPTOR CONSTRAINT header note). */
    return TRUE;
}
