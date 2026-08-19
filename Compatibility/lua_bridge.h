#ifndef COMPATIBILITY_LUA_BRIDGE_H
#define COMPATIBILITY_LUA_BRIDGE_H

#include <stddef.h>

#define LUA_BRIDGE_GLOBALS_INDEX   (-10002)
#define LUA_RESULT_COUNT_GLOBAL    "Compatibility_N"
#define LUA_RESULT_TABLE_GLOBAL    "Compatibility_Res"

char *lua_bridge_escape_literal(const char *script, size_t length);
int lua_bridge_push_result(unsigned int state);


#endif /* COMPATIBILITY_LUA_BRIDGE_H */
