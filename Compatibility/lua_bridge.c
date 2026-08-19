#include <windows.h>

#include "lua_bridge.h"
#include "client_layout.h"

char *lua_bridge_escape_literal(const char *script, size_t length) {
    char *escaped = (char *)HeapAlloc(GetProcessHeap(), 0, length * 4 + 1);
    char *output;
    size_t index;
    if (!escaped) return NULL;
    output = escaped;
    for (index = 0; index < length; index++) {
        unsigned char character = (unsigned char)script[index];
        switch (character) {
        case '\\': *output++ = '\\'; *output++ = '\\'; break;
        case '"': *output++ = '\\'; *output++ = '"'; break;
        case '\n': *output++ = '\\'; *output++ = 'n'; break;
        case '\r': *output++ = '\\'; *output++ = 'r'; break;
        case '\t': *output++ = '\\'; *output++ = 't'; break;
        case 0: HeapFree(GetProcessHeap(), 0, escaped); return NULL;
        default:
            if (character < 0x20 || character >= 0x80) {
                *output++ = '\\';
                *output++ = (char)('0' + character / 100);
                *output++ = (char)('0' + (character / 10) % 10);
                *output++ = (char)('0' + character % 10);
            } else {
                *output++ = (char)character;
            }
        }
    }
    *output = 0;
    return escaped;
}

typedef void (__cdecl *LuaGetFieldFunction)(unsigned int, int, const char *);
typedef double (__cdecl *LuaToNumberFunction)(unsigned int, int);
typedef void (__cdecl *LuaRawGetIntegerFunction)(unsigned int, int, int);
typedef int (__cdecl *LuaGetTopFunction)(unsigned int);
typedef void (__cdecl *LuaRemoveFunction)(unsigned int, int);

int lua_bridge_push_result(unsigned int state) {
    LuaGetFieldFunction getField = (LuaGetFieldFunction)LUA_GETFIELD;
    LuaToNumberFunction toNumber = (LuaToNumberFunction)LUA_TONUMBER;
    LuaRawGetIntegerFunction rawGetInteger = (LuaRawGetIntegerFunction)LUA_RAWGETI;
    LuaGetTopFunction getTop = (LuaGetTopFunction)LUA_GETTOP;
    LuaRemoveFunction remove = (LuaRemoveFunction)LUA_REMOVE;
    int count;
    int tableIndex;
    int index;

    getField(state, LUA_BRIDGE_GLOBALS_INDEX, LUA_RESULT_COUNT_GLOBAL);
    count = (int)toNumber(state, -1);
    remove(state, -1);
    getField(state, LUA_BRIDGE_GLOBALS_INDEX, LUA_RESULT_TABLE_GLOBAL);
    tableIndex = getTop(state);
    for (index = 1; index <= count; index++) rawGetInteger(state, tableIndex, index);
    remove(state, tableIndex);
    return count;
}
