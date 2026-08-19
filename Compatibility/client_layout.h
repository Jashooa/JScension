#ifndef COMPATIBILITY_CLIENT_LAYOUT_H
#define COMPATIBILITY_CLIENT_LAYOUT_H

#include <stdint.h>

#define REGISTER_GLOBAL       0x00817f90u
#define READ_STRING_ARG       0x0084e0e0u
#define SECURE_EXEC           0x00819210u
#define FRAME_SCRIPT_STATE    0x00d3f78cu
#define OWNER_KEY             0x00d4139cu
#define LUA_GETFIELD          0x0084e590u
#define LUA_TYPE              0x0084deb0u
#define LUA_REMOVE            0x0084dc50u
#define LUA_TOBOOLEAN         0x0084e0b0u
#define LUA_TONUMBER          0x0084e030u
#define LUA_GETTOP            0x0084dbd0u
#define LUA_RAWGETI           0x0084e670u
#define LUA_PUSHNUMBER        0x0084e2a0u
#define OBJECT_MANAGER_LOOKUP 0x004d4db0u
#define LINE_OF_SIGHT_TRACE   0x007a3b70u
#define CLICK_TO_MOVE          0x00727400u
#define CLICK_TO_MOVE_BASE     0x00ca11d8u
#define ACTIVE_PLAYER_OBJECT   0x004038f0u
#define HANDLE_TERRAIN_CLICK   0x0080c340u
#define PENDING_SPELL_FLAGS    0x00d3f4e0u
#define PENDING_SPELL          0x00d3f4e4u

int client_layout_validate(void (*log_message)(const char *format, ...));

#endif /* COMPATIBILITY_CLIENT_LAYOUT_H */
