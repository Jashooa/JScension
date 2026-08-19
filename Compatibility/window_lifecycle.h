#ifndef COMPATIBILITY_WINDOW_LIFECYCLE_H
#define COMPATIBILITY_WINDOW_LIFECYCLE_H

#include <windows.h>

typedef void (*WindowLifecycleLogFunction)(const char *format, ...);
typedef struct {
    int (*validate_layout)(void);
    void (*on_compatibility_message)(void);
    void (*on_timer)(void);
    void (*fatal_exit)(const char *message);
    WindowLifecycleLogFunction log_message;
} WindowLifecycleCallbacks;

void window_lifecycle_start(const WindowLifecycleCallbacks *callbacks);

#endif /* COMPATIBILITY_WINDOW_LIFECYCLE_H */
