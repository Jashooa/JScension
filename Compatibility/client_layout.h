#ifndef COMPATIBILITY_CLIENT_LAYOUT_H
#define COMPATIBILITY_CLIENT_LAYOUT_H

#include <stdint.h>

/* Lua runtime */
#define LUA_STATE                       0x00d3f78cu
#define LUA_EXECUTE                     0x00819210u
#define LUA_REGISTER_FUNCTION           0x00817f90u
#define LUA_TO_LSTRING                  0x0084e0e0u
#define LUA_FIND_TABLE                  0x0084e590u
#define LUA_TYPE                        0x0084deb0u
#define LUA_REMOVE                      0x0084dc50u
#define LUA_TO_BOOLEAN                  0x0084e0b0u
#define LUA_TO_NUMBER                   0x0084e030u
#define LUA_GET_TOP                     0x0084dbd0u
#define LUA_RAW_GET_INTEGER             0x0084e670u
#define LUA_PUSH_NUMBER                 0x0084e2a0u

/* Object manager */
#define CLNT_OBJ_MGR_OBJECT_PTR         0x004d4db0u
#define CLNT_OBJ_MGR_GET_ACTIVE_PLAYER_OBJ 0x004038f0u

/* Object enumeration and relationships */
#define ENUM_VISIBLE_OBJECTS             0x004d4b30u
#define CGUNIT_C__CAN_ASSIST             0x007293d0u
#define CGUNIT_C__CAN_ATTACK             0x00729740u

/* World */
#define TRACE_LINE                      0x007a3b70u

/* Spell targeting */
#define SPELL_C__HANDLE_TERRAIN_CLICK   0x0080c340u
#define PENDING_SPELL_FLAGS             0x00d3f4e0u
#define PENDING_SPELL                   0x00d3f4e4u

int client_layout_validate(void (*log_message)(const char *format, ...));

#endif /* COMPATIBILITY_CLIENT_LAYOUT_H */
