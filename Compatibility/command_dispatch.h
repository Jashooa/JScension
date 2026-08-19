#ifndef COMPATIBILITY_COMMAND_DISPATCH_H
#define COMPATIBILITY_COMMAND_DISPATCH_H

#include <stddef.h>
#include <windows.h>

typedef void (__cdecl *CommandPushNumberFunction)(unsigned int state, double value);

/* Returns -1 when no internal command matches; otherwise returns the Lua
 * result count after the matching command has handled the request. */
int command_dispatch(unsigned int state, const char *script, size_t length,
                     CommandPushNumberFunction pushNumber);

#endif /* COMPATIBILITY_COMMAND_DISPATCH_H */
