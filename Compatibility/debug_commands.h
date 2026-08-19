#ifndef COMPATIBILITY_DEBUG_COMMANDS_H
#define COMPATIBILITY_DEBUG_COMMANDS_H

#include <stddef.h>
#include "command_dispatch.h"

typedef void (__cdecl *DebugCommandLogFunction)(const char *format, ...);

/* Returns -1 when no debug command matches; otherwise returns its Lua result count. */
int debug_command_dispatch(unsigned int state, const char *script, size_t length,
                           CommandPushNumberFunction pushNumber,
                           DebugCommandLogFunction logMessage);

#endif /* COMPATIBILITY_DEBUG_COMMANDS_H */
