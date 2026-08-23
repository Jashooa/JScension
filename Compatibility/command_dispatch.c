#include <string.h>
#include "client_api.h"
#include "target_selector.h"
#include "command_dispatch.h"
#include "command_parser.h"

static ClientTargetCandidate selected_target_candidates[CLIENT_TARGET_MAX_RESULTS];
static size_t selected_target_count;

static int command_parse_guid_list(CommandInput *input,
                                   uint32_t count,
                                   ClientObjectGuid *guids) {
    uint32_t index;
    if (count > CLIENT_TARGET_MAX_FILTER_GUIDS || (count > 0 && !guids)) return 0;
    for (index = 0; index < count; index++) {
        if (!command_input_parse_guid(input, &guids[index])) return 0;
    }
    return 1;
}


int command_dispatch(unsigned int state, const char *script, size_t length,
                     CommandPushNumberFunction pushNumber) {
    CommandInput input;
    if (command_input_matches_prefix(script, length, "Compatibility_SelectVisibleUnit ", &input)) {
        ClientTargetCandidate *candidates = selected_target_candidates;
        ClientObjectGuid allowed[CLIENT_TARGET_MAX_FILTER_GUIDS];
        ClientObjectGuid excluded[CLIENT_TARGET_MAX_FILTER_GUIDS];
        ClientObjectGuid currentTarget;
        uint32_t category;
        uint32_t criterion;
        uint32_t allowedCount;
        uint32_t excludedCount;
        float maxDistance;
        selected_target_count = 0;
        if (!command_input_parse_uint32(&input, &category) ||
            !command_input_parse_uint32(&input, &criterion) ||
            !command_input_parse_float(&input, &maxDistance) ||
            !command_input_parse_guid(&input, &currentTarget) ||
            !command_input_parse_uint32(&input, &allowedCount) ||
            !command_parse_guid_list(&input, allowedCount, allowed) ||
            !command_input_parse_uint32(&input, &excludedCount) ||
            !command_parse_guid_list(&input, excludedCount, excluded) ||
            !command_input_finished(&input) ||
            !client_select_visible_units(category, criterion, maxDistance, currentTarget,
                                          allowed, allowedCount, excluded, excludedCount,
                                          candidates, CLIENT_TARGET_MAX_RESULTS,
                                          &selected_target_count)) return 0;
        pushNumber(state, (double)selected_target_count);
        return 1;
    }

    if (command_input_matches_prefix(script, length, "Compatibility_SelectedVisibleUnit ", &input)) {
        uint32_t index;
        ClientTargetCandidate *candidate;
        if (!command_input_parse_uint32(&input, &index) ||
            !command_input_finished(&input) ||
            index == 0 || index > selected_target_count) return 0;
        candidate = &selected_target_candidates[index - 1];
        pushNumber(state, (double)candidate->guid.low);
        pushNumber(state, (double)candidate->guid.high);
        pushNumber(state, (double)candidate->allowedIndex);
        pushNumber(state, (double)candidate->health);
        pushNumber(state, (double)candidate->maxHealth);
        pushNumber(state, candidate->distanceSquared);
        return 6;
    }

    if (command_input_matches_prefix(script, length, "Compatibility_Position ", &input)) {
        ClientObjectGuid guid;
        ClientWorldPosition position;
        void *object;
        if (!command_input_parse_guid(&input, &guid) ||
            !command_input_finished(&input) ||
            !client_find_object(guid, CLIENT_UNIT_TYPE_MASK, &object) ||
            !client_read_object_position(object, &position)) return 0;
        pushNumber(state, position.x);
        pushNumber(state, position.y);
        pushNumber(state, position.z);
        return 3;
    }

    if (command_input_matches_prefix(script, length, "Compatibility_UnitCountInRange ", &input)) {
        ClientObjectGuid centerGuid;
        uint32_t relationshipValue;
        ClientUnitRelationship relationship;
        float radius;
        uint32_t count;
        if (!command_input_parse_guid(&input, &centerGuid) ||
            !command_input_parse_uint32(&input, &relationshipValue) ||
            !command_input_parse_float(&input, &radius) ||
            !command_input_finished(&input) ||
            relationshipValue >= CLIENT_UNIT_RELATIONSHIP_COUNT ||
            !client_count_visible_units_in_range(centerGuid, (ClientUnitRelationship)relationshipValue,
                                                  radius, &count)) return 0;
        pushNumber(state, (double)count);
        return 1;
    }

    if (command_input_matches_prefix(script, length, "Compatibility_Scale ", &input)) {
        ClientObjectGuid guid;
        void *object;
        float scale = 1.0f;
        if (!command_input_parse_guid(&input, &guid) ||
            !command_input_finished(&input)) return 0;
        if (client_find_object(guid, CLIENT_UNIT_TYPE_MASK, &object)) client_read_object_scale(object, &scale);
        pushNumber(state, scale);
        return 1;
    }

    if (command_input_matches_prefix(script, length, "Compatibility_PlaceGround ", &input)) {
        ClientTerrainClick terrainClick = {{0, 0}, {0.0f, 0.0f, 0.0f}};
        if (!command_input_parse_float(&input, &terrainClick.location.x) ||
            !command_input_parse_float(&input, &terrainClick.location.y) ||
            !command_input_parse_float(&input, &terrainClick.location.z) ||
            !command_input_finished(&input)) return 0;
        pushNumber(state, client_handle_terrain_click(&terrainClick) ? 1.0 : 0.0);
        return 1;
    }

    if (command_input_matches_prefix(script, length, "Compatibility_LOS ", &input)) {
        ClientWorldPosition start;
        ClientWorldPosition destination;
        float startScale;
        float destinationScale;
        if (!command_input_parse_float(&input, &start.x) ||
            !command_input_parse_float(&input, &start.y) ||
            !command_input_parse_float(&input, &start.z) ||
            !command_input_parse_float(&input, &destination.x) ||
            !command_input_parse_float(&input, &destination.y) ||
            !command_input_parse_float(&input, &destination.z) ||
            !command_input_parse_float(&input, &startScale) ||
            !command_input_parse_float(&input, &destinationScale) ||
            !command_input_finished(&input)) return 0;
        pushNumber(state, client_trace_line_of_sight(start, destination, startScale, destinationScale) ? 1.0 : 0.0);
        return 1;
    }

    return -1;
}
