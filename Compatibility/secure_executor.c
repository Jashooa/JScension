#include <windows.h>
#include <string.h>

#include "client_layout.h"
#include "lua_bridge.h"
#include "secure_executor.h"

#define MAX_SCRIPT_LENGTH 0x100000u

typedef void (__cdecl *LuaExecuteFunction)(const char *, const char *, const char *);

static const char wrapperPrefix[] = "local f,e=loadstring(\"";
static const char wrapperSuffix[] = "\");local function cap(...)return select('#',...),{...}end;if f then local n,t=cap(pcall(f));" LUA_RESULT_COUNT_GLOBAL "=n;" LUA_RESULT_TABLE_GLOBAL "=t else " LUA_RESULT_COUNT_GLOBAL "=2;" LUA_RESULT_TABLE_GLOBAL "={false,e}end";
static const char missingScript[] = LUA_RESULT_COUNT_GLOBAL "=2;" LUA_RESULT_TABLE_GLOBAL "={false,\"Compatibility: no script argument\"}";
static const char invalidScript[] = LUA_RESULT_COUNT_GLOBAL "=2;" LUA_RESULT_TABLE_GLOBAL "={false,\"Compatibility: script contains a NUL byte\"}";
static const char allocationFailure[] = LUA_RESULT_COUNT_GLOBAL "=2;" LUA_RESULT_TABLE_GLOBAL "={false,\"Compatibility: out of memory\"}";

void secure_executor_run(const char *script, size_t length, const char *ownerName) {
    LuaExecuteFunction executeLuaScript = (LuaExecuteFunction)LUA_EXECUTE;
    char *escaped;
    char *wrapper;
    size_t prefixLength;
    size_t suffixLength;
    size_t escapedLength;
    if (!script || length == 0) { executeLuaScript(missingScript, ownerName, ownerName); return; }
    if (length > MAX_SCRIPT_LENGTH) { executeLuaScript(allocationFailure, ownerName, ownerName); return; }
    escaped = lua_bridge_escape_literal(script, length);
    if (!escaped) { executeLuaScript(invalidScript, ownerName, ownerName); return; }
    prefixLength = sizeof(wrapperPrefix) - 1;
    escapedLength = strlen(escaped);
    suffixLength = sizeof(wrapperSuffix) - 1;
    wrapper = (char *)HeapAlloc(GetProcessHeap(), 0, prefixLength + escapedLength + suffixLength + 1);
    if (!wrapper) {
        HeapFree(GetProcessHeap(), 0, escaped);
        executeLuaScript(allocationFailure, ownerName, ownerName);
        return;
    }
    memcpy(wrapper, wrapperPrefix, prefixLength);
    memcpy(wrapper + prefixLength, escaped, escapedLength);
    memcpy(wrapper + prefixLength + escapedLength, wrapperSuffix, suffixLength + 1);
    executeLuaScript(wrapper, ownerName, ownerName);
    HeapFree(GetProcessHeap(), 0, wrapper);
    HeapFree(GetProcessHeap(), 0, escaped);
}
