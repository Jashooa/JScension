#include <windows.h>
#include "client_api.h"
#include "client_layout.h"

#define OBJECT_GUID_OFFSET 0x30u
#define OBJECT_POSITION_LINK_OFFSET 0xd8u
#define OBJECT_POSITION_OFFSET 0x10u
#define OBJECT_DESCRIPTOR_SCAN_END 0x40u
#define OBJECT_FIELD_SCALE_OFFSET 0x10u
#define LINE_OF_SIGHT_FLAGS 0x1020124u
#define EYE_HEIGHT_PER_SCALE 2.1f

typedef void *(__cdecl *ObjectManagerLookupFunction)(uint32_t low, uint32_t high, uint32_t typeMask);
typedef char (__cdecl *LineOfSightTraceFunction)(float *start, float *end, float *hit, float *distance, uint32_t flags, int unknown);
typedef int (__cdecl *HandleTerrainClickFunction)(void *terrainClick);

int client_find_object(ClientObjectGuid guid, uint32_t typeMask, void **object) {
    ObjectManagerLookupFunction lookup = (ObjectManagerLookupFunction)OBJECT_MANAGER_LOOKUP;
    *object = lookup(guid.low, guid.high, typeMask);
    return *object != NULL;
}

int client_read_object_position(void *object, ClientWorldPosition *position) {
    uintptr_t positionLink;
    float *coordinates;
    if (!object || IsBadReadPtr(object, OBJECT_POSITION_LINK_OFFSET + sizeof(uintptr_t))) return 0;
    positionLink = *(uintptr_t *)((unsigned char *)object + OBJECT_POSITION_LINK_OFFSET);
    if (!positionLink || IsBadReadPtr((const void *)(positionLink + OBJECT_POSITION_OFFSET), sizeof(*position))) return 0;
    coordinates = (float *)(positionLink + OBJECT_POSITION_OFFSET);
    position->x = coordinates[0];
    position->y = coordinates[1];
    position->z = coordinates[2];
    return 1;
}

int client_read_object_scale(void *object, float *scale) {
    uintptr_t descriptor;
    uint32_t objectGuidLow;
    uint32_t objectGuidHigh;
    uint32_t offset;
    if (!object || IsBadReadPtr(object, OBJECT_DESCRIPTOR_SCAN_END + sizeof(uintptr_t))) return 0;
    objectGuidLow = *(uint32_t *)((unsigned char *)object + OBJECT_GUID_OFFSET);
    objectGuidHigh = *(uint32_t *)((unsigned char *)object + OBJECT_GUID_OFFSET + sizeof(uint32_t));
    for (offset = 0; offset <= OBJECT_DESCRIPTOR_SCAN_END; offset += sizeof(uintptr_t)) {
        descriptor = *(uintptr_t *)((unsigned char *)object + offset);
        if (descriptor < 0x10000u || IsBadReadPtr((const void *)descriptor, OBJECT_FIELD_SCALE_OFFSET + sizeof(float))) continue;
        if (*(uint32_t *)descriptor != objectGuidLow || *(uint32_t *)(descriptor + sizeof(uint32_t)) != objectGuidHigh) continue;
        *scale = *(float *)(descriptor + OBJECT_FIELD_SCALE_OFFSET);
        return 1;
    }
    return 0;
}

int client_trace_line_of_sight(ClientWorldPosition start, ClientWorldPosition end,
                               float startScale, float endScale) {
    LineOfSightTraceFunction trace = (LineOfSightTraceFunction)LINE_OF_SIGHT_TRACE;
    float startCoordinates[3] = { start.x, start.y, start.z + EYE_HEIGHT_PER_SCALE * startScale };
    float endCoordinates[3] = { end.x, end.y, end.z + EYE_HEIGHT_PER_SCALE * endScale };
    float hit[3] = { 0.0f, 0.0f, 0.0f };
    float distance = 1.0f;
    return trace(startCoordinates, endCoordinates, hit, &distance, LINE_OF_SIGHT_FLAGS, 0) != 0;
}

int client_handle_terrain_click(const ClientTerrainClick *terrainClick) {
    HandleTerrainClickFunction handleTerrainClick = (HandleTerrainClickFunction)HANDLE_TERRAIN_CLICK;
    if (!*(volatile uintptr_t *)PENDING_SPELL) return 0;
    return handleTerrainClick((void *)terrainClick);
}
