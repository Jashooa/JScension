/* compatibility.exe - one-shot injector for compatibility.dll.
 *
 * PURPOSE
 *   Loads compatibility.dll into the running Ascension client. The game
 *   runs as a 32-bit process inside the prefix's Wine; the injector is
 *   executed in the same prefix (via Proton's wine) so its Win32 view of
 *   the game's window and process matches.
 *
 * HOW IT WORKS
 *   The game window (GxWindowClassD3d) is identified by class name; its
 *   thread/process ids come from GetWindowThreadProcessId. The dll path is
 *   written into the game's address space (VirtualAllocEx +
 *   WriteProcessMemory) and LoadLibraryA is executed there via
 *   CreateRemoteThread. The dll then self-drives: it subclasses the window
 *   and posts WM_APP+1, running all further work on the game's own window
 *   thread (see shim.c).
 *
 * THE DLL PATH
 *   No hardcoded paths: by default the injector loads compatibility.dll
 *   from the directory the injector exe itself lives in (resolved via
 *   GetModuleFileNameA, filename stripped, dll name appended). argv[1]
 *   may override with any path. Keep the two files next to each other and
 *   this resolves correctly no matter where they sit.
 *
 * The game's process id obtained here is the WINE-side pid - the Linux pid
 * differs (the process is a wine-preloader under pressure-vessel). This
 * tool only ever talks to the window and the Win32 process handle; the
 * Linux-side pid is found separately (pgrep -f "ascension-live.*Ascension
 * .exe") for /proc memory access.
 *
 * Runs once per session, after world entry. All output is ASCII-only.
 *
 * The load is waited on with a 30s timeout: a wedged LoadLibraryA must
 * wedge the injector, not the user's session.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define LOAD_TIMEOUT_MS 30000

/* Resolve the dll path: compatibility.dll next to this exe. Returns a
 * pointer into `buf` on success, or NULL when the path cannot be
 * determined. The caller fails loudly on NULL: a guessed relative path
 * could load the wrong file. */
static const char* resolve_dll_path(char* buf, size_t buflen)
{
    DWORD n = GetModuleFileNameA(NULL, buf, (DWORD)buflen);
    if (n == 0 || n >= buflen) {
        return NULL;
    }
    {
        char* slash = strrchr(buf, '\\');
        if (!slash) slash = strrchr(buf, '/');
        if (!slash) return NULL;
        *(slash + 1) = 0;             /* keep the trailing separator */
    }
    {
        size_t len = strlen(buf);
        const char name[] = "compatibility.dll";
        if (len + sizeof(name) > buflen) {
            return NULL;
        }
        memcpy(buf + len, name, sizeof(name));
        return buf;
    }
}

int main(int argc, char** argv) {
    (void)argc;

    /* 0. Resolve the dll path up front (and print it - the resolved path
     * is visible even when the game is not running). */
    char dllPathBuf[MAX_PATH];
    const char* dllPath = (argc > 1) ? argv[1]
                                     : resolve_dll_path(dllPathBuf, sizeof(dllPathBuf));
    if (!dllPath) {
        printf("compatibility: cannot resolve dll path; refusing to load\n");
        return 1;
    }
    printf("compatibility: loading %s\n", dllPath);

    /* 1. Find the game window. FindWindowA enumerates top-level windows
     * for the class; the game creates exactly one GxWindowClassD3d window. */
    HWND hwnd = FindWindowA("GxWindowClassD3d", NULL);
    if (!hwnd) {
        printf("compatibility: game window not found\n");
        return 1;
    }
    DWORD winPid = 0, tid = 0;
    tid = GetWindowThreadProcessId(hwnd, &winPid);
    printf("compatibility: window=%p wine-pid=%lu tid=%lu\n", (void*)hwnd,
           (unsigned long)winPid, (unsigned long)tid);

    /* 2. Open the game process with full access (same-user Wine process). */
    HANDLE hProc = OpenProcess(PROCESS_ALL_ACCESS, FALSE, winPid);
    if (!hProc) {
        printf("compatibility: OpenProcess failed: %lu\n", (unsigned long)GetLastError());
        return 1;
    }

    /* 3. Allocate space in the game for the dll path string and copy it. */
    SIZE_T pathLen = (SIZE_T)lstrlenA(dllPath) + 1;
    void* mem = VirtualAllocEx(hProc, NULL, pathLen, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!mem) {
        printf("compatibility: VirtualAllocEx failed: %lu\n", (unsigned long)GetLastError());
        CloseHandle(hProc);
        return 1;
    }
    if (!WriteProcessMemory(hProc, mem, dllPath, pathLen, NULL)) {
        printf("compatibility: WriteProcessMemory failed: %lu\n", (unsigned long)GetLastError());
        VirtualFreeEx(hProc, mem, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return 1;
    }

    /* 4. Run LoadLibraryA(path) inside the game via a remote thread.
     * kernel32 is loaded at the same address in every process of the
     * prefix, so GetProcAddress here yields a valid entry in the game. */
    HMODULE k32 = GetModuleHandleA("kernel32.dll");
    LPTHREAD_START_ROUTINE loadLib =
        (LPTHREAD_START_ROUTINE)GetProcAddress(k32, "LoadLibraryA");
    HANDLE hThread = CreateRemoteThread(hProc, NULL, 0, loadLib, mem, 0, NULL);
    if (!hThread) {
        printf("compatibility: CreateRemoteThread failed: %lu\n", (unsigned long)GetLastError());
        VirtualFreeEx(hProc, mem, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return 1;
    }

    /* 5. Wait for the load (bounded); the thread exit code is the module
     * handle. On timeout, leave the thread to finish on its own and exit:
     * the dll self-drives once loaded, and killing a thread inside
     * LoadLibraryA risks deadlocking the loader lock. */
    if (WaitForSingleObject(hThread, LOAD_TIMEOUT_MS) == WAIT_TIMEOUT) {
        printf("compatibility: warning - load thread still running after %dms; leaving it\n",
               LOAD_TIMEOUT_MS);
        CloseHandle(hThread);
        VirtualFreeEx(hProc, mem, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return 2;
    }
    DWORD exitCode = 0;
    GetExitCodeThread(hThread, &exitCode);
    printf("compatibility: loaded in game (hmod=%p)\n", (void*)exitCode);

    /* 6. Clean up our remote allocations and handles. The dll stays
     * loaded and self-drives from here. */
    CloseHandle(hThread);
    VirtualFreeEx(hProc, mem, 0, MEM_RELEASE);
    CloseHandle(hProc);
    printf("compatibility: done - check compatibility.log for 'self-test ok=1'\n");
    return 0;
}
