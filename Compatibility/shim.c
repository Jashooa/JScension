/* compatibility.dll - the Compatibility bridge for the Ascension 3.3.5a client.
 *
 * This file owns the DLL entry point, logging, trust-owner registration, and the
 * registered callback. The callback runs on the game window thread and delegates:
 *
 *   - client_layout: client addresses and layout validation
 *   - command_dispatch/debug_commands: internal native commands
 *   - secure_executor/lua_bridge: trusted script execution and result replay
 *   - trust_manifest: trusted owner selection
 *   - window_lifecycle: subclassing, registration messages, and keepalive timing
 *
 * The callback descriptor is part of the client ABI. The game reads bytes at
 * callback+0x10 and callback+0x4d..0x4f as metadata. Compatibility_cb therefore
 * remains a naked stub with fixed padding and descriptor bytes b3 01 00. The
 * build verifies those bytes after every rebuild. Do not replace the stub with
 * an ordinary function or unload this DLL while the global is registered.
 *
 * Registration and client calls happen only after layout validation. The
 * window lifecycle schedules them on the game's window thread, where FrameScript
 * is idle between messages. Logs stay ASCII-only and live beside this DLL.
 */
#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "client_api.h"
#include "lua_bridge.h"
#include "command_dispatch.h"
#include "debug_commands.h"
#include "trust_manifest.h"
#include "client_layout.h"
#include "secure_executor.h"
#include "window_lifecycle.h"
#include "common.h"

/* Lua 5.1 type tag used to verify the registered global. */
#define LUA_TYPE_FUNCTION 6

/* Manifest layout bounds and printable-name checks. */
#define MAX_TRUSTED_NAME_LENGTH 63
#define SSO_INLINE_LENGTH       15
#define MINIMUM_HEAP_ADDRESS    0x10000

/* Keep log records bounded while reserving room for the FrameScript suffix. */
#define LOG_BUFFER_SIZE 512
#define LOG_SUFFIX_RESERVE 20

/* Trusted-owner manifest layout. */
#define MANIFEST_ENTRY_SIZE          0x1c
#define MANIFEST_NAME_LENGTH_OFFSET  0x10
#define MANIFEST_TRUSTED_FLAG_OFFSET 0x18
#define MAX_MANIFEST_ENTRIES         400

typedef void (__cdecl *LuaRegisterFunction)(const char *name, void *callback);
typedef const char *(__cdecl *LuaToLStringFunction)(unsigned int state, int index,
                                                    unsigned int *length);
typedef void (__cdecl *LuaExecuteFunction)(const char *script,
                                           const char *ownerName,
                                           const char *callerName);
typedef void (__cdecl *LuaFindTableFunction)(unsigned int state, int index,
                                             const char *name);
typedef int (__cdecl *LuaTypeFunction)(unsigned int state, int index);
typedef void (__cdecl *LuaRemoveFunction)(unsigned int state, int index);
typedef int (__cdecl *LuaToBooleanFunction)(unsigned int state, int index);
typedef void (__cdecl *LuaRawGetIntegerFunction)(unsigned int state, int index, int item);

/* Registration state belongs to the game-thread callbacks; window mechanics
 * live in window_lifecycle.c. */
static int g_compatibility_registered = 0;
static unsigned long g_last_lua_state = 0;
static char g_owner[MAX_TRUSTED_NAME_LENGTH + 1];
static const char *g_owner_name = NULL;
static HMODULE g_module_handle = NULL;
static int g_waiting_logged = 0;
static unsigned long g_anticheat_singleton = 0;
static char g_log_path[MAX_PATH];

/* ---------- logging ---------- */

/* Store the log beside the module so the injector and shim share one artifact. */
static void initialize_log_path(HMODULE moduleHandle) {
    static const char logFileName[] = "compatibility.log";
    DWORD pathLength = GetModuleFileNameA(moduleHandle, g_log_path, MAX_PATH);
    char *lastSeparator = NULL;
    DWORD pathIndex;

    if (pathLength >= MAX_PATH) pathLength = MAX_PATH - 1;
    for (pathIndex = 0; pathIndex < pathLength; pathIndex++) {
        if (g_log_path[pathIndex] == '\\' || g_log_path[pathIndex] == '/') {
            lastSeparator = g_log_path + pathIndex;
        }
    }
    if (lastSeparator) memcpy(lastSeparator + 1, logFileName, sizeof(logFileName));
    else memcpy(g_log_path, logFileName, sizeof(logFileName));
}

static void write_log(const char *buffer, int length) {
    HANDLE logHandle = CreateFileA(g_log_path, FILE_APPEND_DATA,
                                    FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS,
                                    FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD bytesWritten;
    if (logHandle == INVALID_HANDLE_VALUE) return;
    WriteFile(logHandle, buffer, (DWORD)length, &bytesWritten, NULL);
    CloseHandle(logHandle);
}

/* Keep every line bounded. Logging must not corrupt shim state while reporting
 * a client-layout or injection failure. */
static void log_messagef(const char *format, ...) {
    SYSTEMTIME currentTime;
    va_list arguments;
    char buffer[LOG_BUFFER_SIZE];
    int prefixLength;
    int messageLength;
    int totalLength;

    GetLocalTime(&currentTime);
    prefixLength = snprintf(buffer, sizeof(buffer), "[%02u:%02u:%02u.%03u] [%lu] ",
                            currentTime.wHour, currentTime.wMinute,
                            currentTime.wSecond, currentTime.wMilliseconds,
                            (unsigned long)GetCurrentThreadId());
    if (prefixLength < 0 || prefixLength >= (int)sizeof(buffer)) return;

    va_start(arguments, format);
    messageLength = vsnprintf(buffer + prefixLength,
                               sizeof(buffer) - (size_t)prefixLength, format, arguments);
    va_end(arguments);
    if (messageLength < 0 ||
        messageLength >= (int)(sizeof(buffer) - (size_t)prefixLength)) {
        messageLength = (int)sizeof(buffer) - prefixLength - 1;
    }
    totalLength = prefixLength + messageLength;
    if (totalLength > (int)sizeof(buffer) - LOG_SUFFIX_RESERVE) {
        totalLength = (int)sizeof(buffer) - LOG_SUFFIX_RESERVE;
    }
    totalLength += snprintf(buffer + totalLength, sizeof(buffer) - (size_t)totalLength,
                            " (fs=%08lx)\r\n",
                            *(volatile unsigned long *)LUA_STATE);
    if (totalLength > 0 && totalLength < (int)sizeof(buffer)) {
        write_log(buffer, totalLength);
    }
}

static void log_message(const char *message) {
    log_messagef("%s", message);
}

static void __attribute__((noreturn)) fatal_exit(const char *message) {
    log_message(message);
    FreeLibraryAndExitThread(g_module_handle, 1);
}

/* ---------- trusted-owner manifest ---------- */

/* Locate the trusted-owner manifest by its stable in-memory shape. The
 * Extensions.dll image moves, but the singleton still contains:
 *   [vftable in module][heap vector begin][heap vector end] */

static int valid_manifest_entry(unsigned long entryAddress) {
    unsigned int nameLength;
    unsigned int trustedFlag;
    unsigned int nameIndex;
    const char *name;

    if (IsBadReadPtr((void *)entryAddress, MANIFEST_ENTRY_SIZE)) return 0;
    nameLength = *(unsigned int *)(entryAddress + MANIFEST_NAME_LENGTH_OFFSET);
    trustedFlag = *(unsigned int *)(entryAddress + MANIFEST_TRUSTED_FLAG_OFFSET);
    if (nameLength > MAX_TRUSTED_NAME_LENGTH || trustedFlag > 1) return 0;
    name = (nameLength <= SSO_INLINE_LENGTH)
        ? (const char *)entryAddress
        : *(const char **)entryAddress;
    if ((unsigned long)name < MINIMUM_HEAP_ADDRESS ||
        IsBadStringPtrA(name, (UINT_PTR)nameLength + 1)) return 0;
    for (nameIndex = 0; nameIndex < nameLength; nameIndex++) {
        unsigned char character = (unsigned char)name[nameIndex];
        if (character < 0x20 || character > 0x7e) return 0;
    }
    return 1;
}

static unsigned long find_anticheat_singleton(void) {
    HMODULE extensionsModule = GetModuleHandleA("Extensions.dll");
    IMAGE_DOS_HEADER *dosHeader;
    IMAGE_NT_HEADERS *ntHeaders;
    IMAGE_SECTION_HEADER *sectionHeader;
    unsigned long moduleBase;
    unsigned long moduleImageSize;
    unsigned long sectionIndex;

    if (!extensionsModule) {
        log_message("ac: Extensions.dll not found");
        return 0;
    }
    dosHeader = (IMAGE_DOS_HEADER *)extensionsModule;
    if (IsBadReadPtr(dosHeader, sizeof(*dosHeader)) ||
        dosHeader->e_magic != IMAGE_DOS_SIGNATURE) {
        log_message("ac: bad DOS header");
        return 0;
    }
    ntHeaders = (IMAGE_NT_HEADERS *)((unsigned char *)extensionsModule +
                                      dosHeader->e_lfanew);
    if (IsBadReadPtr(ntHeaders, sizeof(*ntHeaders)) ||
        ntHeaders->Signature != IMAGE_NT_SIGNATURE) {
        log_message("ac: bad NT header");
        return 0;
    }
    moduleBase = (unsigned long)extensionsModule;
    moduleImageSize = ntHeaders->OptionalHeader.SizeOfImage;
    sectionHeader = IMAGE_FIRST_SECTION(ntHeaders);
    for (sectionIndex = 0;
         sectionIndex < ntHeaders->FileHeader.NumberOfSections;
         sectionIndex++, sectionHeader++) {
        unsigned long sectionStart;
        unsigned long sectionSize;
        unsigned long candidateAddress;
        if (!(sectionHeader->Characteristics & IMAGE_SCN_MEM_WRITE)) continue;
        sectionStart = moduleBase + sectionHeader->VirtualAddress;
        sectionSize = sectionHeader->Misc.VirtualSize
            ? sectionHeader->Misc.VirtualSize
            : sectionHeader->SizeOfRawData;
        if (sectionStart + sectionSize > moduleBase + moduleImageSize) {
            sectionSize = moduleBase + moduleImageSize - sectionStart;
        }
        for (candidateAddress = sectionStart;
             candidateAddress + 12 <= sectionStart + sectionSize;
             candidateAddress += 4) {
            unsigned long vtableAddress = *(unsigned long *)candidateAddress;
            unsigned long vectorBegin = *(unsigned long *)(candidateAddress + 4);
            unsigned long vectorEnd = *(unsigned long *)(candidateAddress + 8);
            unsigned long vectorSize;
            if (!(vtableAddress >= moduleBase &&
                  vtableAddress < moduleBase + moduleImageSize)) continue;
            if (!(vectorBegin > MINIMUM_HEAP_ADDRESS &&
                  (vectorBegin < moduleBase ||
                   vectorBegin >= moduleBase + moduleImageSize))) continue;
            if (vectorEnd <= vectorBegin) continue;
            vectorSize = vectorEnd - vectorBegin;
            if (vectorSize % MANIFEST_ENTRY_SIZE ||
                vectorSize / MANIFEST_ENTRY_SIZE < 1 ||
                vectorSize / MANIFEST_ENTRY_SIZE > MAX_MANIFEST_ENTRIES) continue;
            if (!valid_manifest_entry(vectorBegin)) continue;
            log_messagef("ac: singleton resolved at %08lx (vftable %08lx, %u entries)",
                         candidateAddress, vtableAddress,
                         (unsigned)(vectorSize / MANIFEST_ENTRY_SIZE));
            return candidateAddress;
        }
    }
    return 0;
}

/* ---------- layout validation ---------- */

/* Client addresses and byte snapshots have one owner: client_layout.c. */
static int validate_layout(void) {
    int valid = client_layout_validate(log_messagef);
    if (!valid) {
        log_message("layout: REFUSING - client layout changed; rebuild with new snapshots");
    }
    return valid;
}

/* ---------- the Compatibility Lua global ---------- */

/* The callback reads a script, handles native commands, then delegates all
 * other scripts to the trusted executor. */

static int __cdecl Compatibility_body(unsigned int state) __asm__("Compatibility_body") __attribute__((used));
static int __cdecl Compatibility_body(unsigned int state) {
    LuaToLStringFunction readLuaString = (LuaToLStringFunction)LUA_TO_LSTRING;
    unsigned int scriptLength = 0;
    const char *script = readLuaString(state, 1, &scriptLength);
    int commandResult = command_dispatch(
        state, script, scriptLength, (CommandPushNumberFunction)LUA_PUSH_NUMBER);
    if (commandResult >= 0) return commandResult;
    commandResult = debug_command_dispatch(
        state, script, scriptLength, (CommandPushNumberFunction)LUA_PUSH_NUMBER,
        log_messagef);
    if (commandResult >= 0) return commandResult;
    secure_executor_run(script, scriptLength, g_owner_name);
    return lua_bridge_push_result(state);
}

/* The game reads the registered callback's code bytes as metadata. The naked
 * stub pins the required descriptor bytes at callback+0x4d..0x4f. */
__attribute__((naked)) static int __cdecl Compatibility_cb(unsigned int state) {
    __asm__ __volatile__(
        ".rept 0x45\n\t.byte 0x90\n\t.endr\n\t"
        "jmp Compatibility_body\n\t"
        ".byte 0x90,0x90,0x90\n\t"
        ".byte 0xb3,0x01,0x00\n\t"
    );
}

/* ---------- registration ---------- */

/* Registration runs on the game window thread, after the lifecycle module posts
 * its message. A silent self-test confirms that protected-call results replay. */
static void self_test_registration(void) {
    unsigned long luaState = *(volatile unsigned long *)LUA_STATE;
    LuaFindTableFunction findTable;
    LuaToBooleanFunction readBoolean;
    LuaRawGetIntegerFunction readRawInteger;
    LuaRemoveFunction removeStackValue;
    if (!luaState) return;

    findTable = (LuaFindTableFunction)LUA_FIND_TABLE;
    readBoolean = (LuaToBooleanFunction)LUA_TO_BOOLEAN;
    readRawInteger = (LuaRawGetIntegerFunction)LUA_RAW_GET_INTEGER;
    removeStackValue = (LuaRemoveFunction)LUA_REMOVE;
    findTable(luaState, LUA_BRIDGE_GLOBALS_INDEX, LUA_RESULT_TABLE_GLOBAL);
    readRawInteger(luaState, -1, 1);
    log_messagef("compatibility: self-test ok=%d", readBoolean(luaState, -1));
    removeStackValue(luaState, -1);
    removeStackValue(luaState, -1);
}

static int register_compatibility(void) {
    LuaRegisterFunction registerLuaGlobal = (LuaRegisterFunction)LUA_REGISTER_FUNCTION;
    LuaExecuteFunction executeLuaScript = (LuaExecuteFunction)LUA_EXECUTE;
    unsigned long luaState;

    if (!g_anticheat_singleton) {
        g_anticheat_singleton = find_anticheat_singleton();
        if (!g_anticheat_singleton) {
            if (!g_waiting_logged) {
                log_message("compatibility: manifest not populated yet - waiting (retrying every 1s)");
                g_waiting_logged = 1;
            }
            return 0;
        }
    }
    if (!g_owner_name) {
        if (!trust_manifest_choose_owner(g_anticheat_singleton, g_owner,
                                         sizeof(g_owner), log_messagef)) {
            log_message("compatibility: NO trusted owner - refusing to register (addon probe will report)");
            return 0;
        }
        g_owner_name = g_owner;
    }
    luaState = *(volatile unsigned long *)LUA_STATE;
    if (!luaState || IsBadReadPtr((void *)luaState, 0x100)) {
        log_message("compatibility: Lua state invalid - not registering");
        return 0;
    }
    registerLuaGlobal("Compatibility", (void *)Compatibility_cb);
    g_compatibility_registered = 1;
    log_message("compatibility: Compatibility registered");
    executeLuaScript("local function cap(...)return select('#',...),{...}end;local n,t=cap(pcall(Compatibility,'-- self-test'));"
                     LUA_RESULT_COUNT_GLOBAL "=n;" LUA_RESULT_TABLE_GLOBAL "=t",
                     g_owner_name, g_owner_name);
    self_test_registration();
    g_last_lua_state = *(volatile unsigned long *)LUA_STATE;
    return 1;
}

static int is_compatibility_alive(unsigned int state) {
    LuaFindTableFunction findTable = (LuaFindTableFunction)LUA_FIND_TABLE;
    LuaTypeFunction readType = (LuaTypeFunction)LUA_TYPE;
    LuaRemoveFunction removeStackValue = (LuaRemoveFunction)LUA_REMOVE;
    int valueType;
    findTable(state, LUA_BRIDGE_GLOBALS_INDEX, "Compatibility");
    valueType = readType(state, -1);
    removeStackValue(state, -1);
    return valueType == LUA_TYPE_FUNCTION;
}

/* ---------- window lifecycle ---------- */

static void handle_keepalive_timer(void) {
    unsigned long luaState = *(volatile unsigned long *)LUA_STATE;
    if (!luaState) return;
    if (luaState != g_last_lua_state) {
        g_last_lua_state = luaState;
        return;
    }
    if (!g_compatibility_registered) {
        register_compatibility();
        return;
    }
    if (is_compatibility_alive(luaState)) return;
    log_message("compatibility: Compatibility global missing - re-registering");
    register_compatibility();
}

static void handle_compatibility_message(void) {
    log_message("subclass: WM_COMPATIBILITY on window thread");
    if (!g_compatibility_registered) {
        register_compatibility();
    } else {
        log_message("subclass: already registered, skipping");
    }
}

static void start_window_lifecycle(void) {
    WindowLifecycleCallbacks callbacks;
    callbacks.validate_layout = validate_layout;
    callbacks.on_compatibility_message = handle_compatibility_message;
    callbacks.on_timer = handle_keepalive_timer;
    callbacks.fatal_exit = fatal_exit;
    callbacks.log_message = log_messagef;
    window_lifecycle_start(&callbacks);
}

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    (void)lpvReserved;
    if (fdwReason == DLL_PROCESS_ATTACH) {
        g_module_handle = hinstDLL;
        initialize_log_path(hinstDLL);
        DisableThreadLibraryCalls(hinstDLL);
        log_message("dllmain: compatibility attached");
        start_window_lifecycle();
    }
    /* DLL_PROCESS_DETACH: the subclass and timer die with the process. */
    return TRUE;
}
