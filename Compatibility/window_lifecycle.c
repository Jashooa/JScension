#include <windows.h>
#include "common.h"
#include "window_lifecycle.h"

#define WM_COMPATIBILITY (WM_APP + 1)
#define COMPATIBILITY_TIMER_ID 0x4A4A
#define COMPATIBILITY_TIMER_MS 1000
#define WATCHDOG_INTERVAL_MS 500

typedef struct {
    HWND window;
    WNDPROC previousProcedure;
} WindowLifecycleState;
static LRESULT CALLBACK lifecycle_window_procedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam);


static WindowLifecycleCallbacks lifecycleCallbacks;
static WindowLifecycleState lifecycleState;

static void install_subclass(HWND window) {
    WNDPROC currentProcedure = (WNDPROC)GetWindowLongPtrA(window, GWLP_WNDPROC);
    LONG_PTR previousProcedure;
    if (currentProcedure == lifecycle_window_procedure) return;
    SetLastError(ERROR_SUCCESS);
    previousProcedure = SetWindowLongPtrA(window, GWLP_WNDPROC, (LONG_PTR)lifecycle_window_procedure);
    if (!previousProcedure && GetLastError() != ERROR_SUCCESS) {
        lifecycleCallbacks.log_message("watchdog: SetWindowLongPtr failed: %lu", (unsigned long)GetLastError());
        return;
    }
    lifecycleState.previousProcedure = (WNDPROC)previousProcedure;
    if (!PostMessageA(window, WM_COMPATIBILITY, 0, 0)) {
        lifecycleCallbacks.log_message("watchdog: PostMessage failed: %lu", (unsigned long)GetLastError());
    }
    lifecycleCallbacks.log_message("watchdog: subclassed hwnd %08lx (prev proc %08lx)",
                                   (unsigned long)window, (unsigned long)previousProcedure);
}

static LRESULT CALLBACK lifecycle_window_procedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_COMPATIBILITY) {
        lifecycleCallbacks.on_compatibility_message();
        SetTimer(window, COMPATIBILITY_TIMER_ID, COMPATIBILITY_TIMER_MS, NULL);
        lifecycleCallbacks.log_message("subclass: keepalive timer set (1s)");
        return 0;
    }
    if (message == WM_TIMER && wParam == COMPATIBILITY_TIMER_ID) {
        lifecycleCallbacks.on_timer();
        return 0;
    }
    if (lifecycleState.previousProcedure) {
        return CallWindowProcA(lifecycleState.previousProcedure, window, message, wParam, lParam);
    }
    return DefWindowProcA(window, message, wParam, lParam);
}

static DWORD WINAPI watchdog_thread(LPVOID parameter) {
    (void)parameter;
    for (;;) {
        HWND window = FindWindowA(GAME_WINDOW_CLASS, NULL);
        if (window && (window != lifecycleState.window ||
                       (WNDPROC)GetWindowLongPtrA(window, GWLP_WNDPROC) != lifecycle_window_procedure)) {
            lifecycleState.window = window;
            install_subclass(window);
        }
        Sleep(WATCHDOG_INTERVAL_MS);
    }
}

static DWORD WINAPI setup_thread(LPVOID parameter) {
    HANDLE watchdog;
    (void)parameter;
    lifecycleCallbacks.log_message("setup: looking for game window");
    if (!FindWindowA(GAME_WINDOW_CLASS, NULL)) {
        lifecycleCallbacks.fatal_exit("setup: game window not found - unload (inject once the game is up)");
    }
    if (!lifecycleCallbacks.validate_layout()) {
        lifecycleCallbacks.fatal_exit("setup: layout mismatch - unloading (re-inject a matching build)");
    }
    watchdog = CreateThread(NULL, 0, watchdog_thread, NULL, 0, NULL);
    if (!watchdog) {
        lifecycleCallbacks.fatal_exit("setup: watchdog thread failed to start - unloading");
    }
    CloseHandle(watchdog);
    lifecycleCallbacks.log_message("setup: validated; watchdog started");
    return 0;
}

void window_lifecycle_start(const WindowLifecycleCallbacks *callbacks) {
    HANDLE setup;
    lifecycleCallbacks = *callbacks;
    lifecycleState.window = NULL;
    lifecycleState.previousProcedure = NULL;
    setup = CreateThread(NULL, 0, setup_thread, NULL, 0, NULL);
    if (setup) CloseHandle(setup);
}
