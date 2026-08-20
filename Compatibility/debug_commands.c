/* Debug-only native commands kept outside the registered callback. */
#include <windows.h>

#include "client_layout.h"
#include "command_parser.h"
#include "debug_commands.h"

#define PROBE_DEFAULT_TYPE_MASK 0x08u
#define PROBE_BYTES_PER_ROW 16
#define PROBE_ROW_COUNT 16
#define PROBE_READ_LENGTH (PROBE_BYTES_PER_ROW * PROBE_ROW_COUNT)

typedef void *(__cdecl *GetPlayerObjectFunction)(void);
typedef int (__thiscall *ClickToMoveFunction)(void *, int, ClientObjectGuid *, float *, int);
typedef void *(__cdecl *ObjectManagerLookupFunction)(unsigned int, unsigned int, unsigned int);

static int dispatch_click_to_move(unsigned int state, const char *script, size_t length,
                                  CommandPushNumberFunction pushNumber,
                                  DebugCommandLogFunction logMessage) {
    static const char prefix[] = "Compatibility_CTM ";
    CommandInput input;
    float position[3];
    ClientObjectGuid targetGuid = {0, 0};
    void *player;
    int result;
    unsigned int coordinateIndex;

    if (!command_input_matches_prefix(script, length, prefix, &input)) return -1;
    for (coordinateIndex = 0; coordinateIndex < 3; coordinateIndex++) {
        if (!command_input_parse_float(&input, &position[coordinateIndex])) return 0;
    }
    if (!command_input_finished(&input)) return 0;
    player = ((GetPlayerObjectFunction)CLNT_OBJ_MGR_GET_ACTIVE_PLAYER_OBJ)();
    if (!player) return 0;
    result = ((ClickToMoveFunction)CGPLAYER_C__CLICK_TO_MOVE)(player, 1, &targetGuid, position, 0);
    logMessage("ctm: ctm(%08lx, 1, (%f,%f,%f)) = %d",
               (unsigned long)player, position[0], position[1], position[2], result);
    pushNumber(state, result ? 1.0 : 0.0);
    return 1;
}

static int dispatch_object_probe(const char *script, size_t length,
                                 DebugCommandLogFunction logMessage) {
    static const char prefix[] = "Compatibility_Probe ";
    CommandInput input;
    ClientObjectGuid guid;
    ClientObjectGuid maskGuid;
    unsigned int typeMask = PROBE_DEFAULT_TYPE_MASK;
    void *object;
    unsigned int row;

    if (!command_input_matches_prefix(script, length, prefix, &input)) return -1;
    if (!command_input_parse_guid(&input, &guid)) {
        logMessage("probe: no GUID");
        return 0;
    }
    if (!command_input_finished(&input)) {
        if (!command_input_parse_guid(&input, &maskGuid) || maskGuid.high != 0 ||
            !command_input_finished(&input)) return 0;
        typeMask = maskGuid.low;
    }
    logMessage("probe: lookup(%08x%08x, %08x)", guid.high, guid.low, typeMask);
    object = ((ObjectManagerLookupFunction)CLNT_OBJ_MGR_OBJECT_PTR)(guid.low, guid.high, typeMask);
    logMessage("probe: result = %08lx", (unsigned long)object);
    if (object && !IsBadReadPtr(object, PROBE_READ_LENGTH)) {
        unsigned char *bytes = (unsigned char *)object;
        for (row = 0; row < PROBE_ROW_COUNT; row++) {
            char line[128];
            int lineLength = 0;
            unsigned int column;
            lineLength += wsprintfA(line + lineLength, "  +%02x: ", row * PROBE_BYTES_PER_ROW);
            for (column = 0; column < PROBE_BYTES_PER_ROW; column++) {
                lineLength += wsprintfA(line + lineLength, "%02x ", bytes[row * PROBE_BYTES_PER_ROW + column]);
            }
            logMessage("%s", line);
        }
    }
    return 0;
}

int debug_command_dispatch(unsigned int state, const char *script, size_t length,
                           CommandPushNumberFunction pushNumber,
                           DebugCommandLogFunction logMessage) {
    int result = dispatch_click_to_move(state, script, length, pushNumber, logMessage);
    if (result >= 0) return result;
    return dispatch_object_probe(script, length, logMessage);
}
