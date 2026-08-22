#include <float.h>
#include <windows.h>
#include "client_api.h"
#include "client_layout.h"

#define OBJECT_GUID_OFFSET 0x30u
#define OBJECT_POSITION_LINK_OFFSET 0xd8u
#define OBJECT_POSITION_OFFSET 0x10u
#define OBJECT_DESCRIPTOR_SCAN_END 0x40u
#define OBJECT_FIELD_SCALE_INDEX 0x4u
#define OBJECT_FIELD_SCALE_OFFSET (OBJECT_FIELD_SCALE_INDEX * sizeof(uint32_t))
#define UNIT_FIELD_HEALTH_INDEX 0x18u
#define UNIT_FIELD_HEALTH_OFFSET (UNIT_FIELD_HEALTH_INDEX * sizeof(uint32_t))
#define MINIMUM_OBJECT_ADDRESS 0x10000u
#define LINE_OF_SIGHT_FLAGS 0x1020124u
#define EYE_HEIGHT_PER_SCALE 2.1f

typedef void *(__cdecl *ObjectManagerLookupFunction)(uint32_t low, uint32_t high, uint32_t typeMask);
typedef void *(__cdecl *ActivePlayerObjectFunction)(void);

typedef int (__cdecl *VisibleObjectCallbackFunction)(uint32_t low, uint32_t high,
                                                     uintptr_t context);
typedef int (__cdecl *EnumerateVisibleObjectsFunction)(VisibleObjectCallbackFunction callback,
                                                        uintptr_t context);
typedef char (__thiscall *UnitCanAssistFunction)(void *unit, void *target, int includeDead);
typedef char (__thiscall *UnitCanAttackFunction)(void *unit, void *target);
typedef char (__cdecl *TraceLineFunction)(float *start, float *end, float *traceHitCoordinates, float *traceDistance, uint32_t flags, int unknown);
typedef int (__cdecl *HandleTerrainClickFunction)(void *terrainClick);

typedef struct {
    void *activePlayerObject;
    void *centerObject;
    ClientWorldPosition centerPosition;
    ClientUnitRelationship relationship;
    double radiusSquared;
    uint32_t count;
} UnitRangeCountContext;

static int client_find_object_descriptor(void *object, uintptr_t *descriptor) {
    uint32_t objectGuidLow;
    uint32_t objectGuidHigh;
    uint32_t offset;
    if (!object || IsBadReadPtr(object, OBJECT_DESCRIPTOR_SCAN_END + sizeof(uintptr_t))) return 0;
    objectGuidLow = *(uint32_t *)((unsigned char *)object + OBJECT_GUID_OFFSET);
    objectGuidHigh = *(uint32_t *)((unsigned char *)object + OBJECT_GUID_OFFSET + sizeof(uint32_t));
    for (offset = 0; offset <= OBJECT_DESCRIPTOR_SCAN_END; offset += sizeof(uintptr_t)) {
        uintptr_t candidate = *(uintptr_t *)((unsigned char *)object + offset);
        if (candidate < MINIMUM_OBJECT_ADDRESS ||
            IsBadReadPtr((const void *)candidate, sizeof(ClientObjectGuid))) continue;
        if (*(uint32_t *)candidate != objectGuidLow ||
            *(uint32_t *)(candidate + sizeof(uint32_t)) != objectGuidHigh) continue;
        *descriptor = candidate;
        return 1;
    }
    return 0;
}

static int client_read_object_field(void *object, uint32_t fieldOffset, uint32_t *value) {
    uintptr_t descriptor;
    if (!client_find_object_descriptor(object, &descriptor) ||
        IsBadReadPtr((const void *)(descriptor + fieldOffset), sizeof(*value))) return 0;
    *value = *(uint32_t *)(descriptor + fieldOffset);
    return 1;
}

static int client_read_object_health(void *object, uint32_t *health) {
    return client_read_object_field(object, UNIT_FIELD_HEALTH_OFFSET, health);
}

int client_find_object(ClientObjectGuid guid, uint32_t typeMask, void **object) {
    ObjectManagerLookupFunction objectManagerLookup = (ObjectManagerLookupFunction)CLNT_OBJ_MGR_OBJECT_PTR;
    *object = objectManagerLookup(guid.low, guid.high, typeMask);
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
    union {
        uint32_t integer;
        float real;
    } value;
    if (!client_read_object_field(object, OBJECT_FIELD_SCALE_OFFSET, &value.integer)) return 0;
    *scale = value.real;
    return 1;
}

static int client_unit_is_living(void *object) {
    uint32_t health;
    return client_read_object_health(object, &health) && health > 0;
}

static int client_relationship_matches(UnitRangeCountContext *context, void *candidate) {
    UnitCanAssistFunction canAssist;
    UnitCanAttackFunction canAttack;
    switch (context->relationship) {
    case CLIENT_UNIT_RELATIONSHIP_ANY:
        return 1;
    case CLIENT_UNIT_RELATIONSHIP_ENEMY:
        canAttack = (UnitCanAttackFunction)CGUNIT_C__CAN_ATTACK;
        return canAttack(context->activePlayerObject, candidate) != 0;
    case CLIENT_UNIT_RELATIONSHIP_FRIENDLY:
        canAssist = (UnitCanAssistFunction)CGUNIT_C__CAN_ASSIST;
        return canAssist(context->activePlayerObject, candidate, 0) != 0;
    case CLIENT_UNIT_RELATIONSHIP_PLAYER:
        return candidate == context->activePlayerObject;
    default:
        return 0;
    }
}

static double squared_distance(ClientWorldPosition first, ClientWorldPosition second) {
    double x = (double)first.x - (double)second.x;
    double y = (double)first.y - (double)second.y;
    double z = (double)first.z - (double)second.z;
    return x * x + y * y + z * z;
}

static int count_visible_unit(uint32_t low, uint32_t high, uintptr_t contextAddress) {
    UnitRangeCountContext *context = (UnitRangeCountContext *)contextAddress;
    ClientObjectGuid guid = { low, high };
    ClientWorldPosition position;
    void *object;
    if (!client_find_object(guid, CLIENT_UNIT_TYPE_MASK, &object) ||
        !client_unit_is_living(object) ||
        !client_relationship_matches(context, object) ||
        !client_read_object_position(object, &position) ||
        squared_distance(context->centerPosition, position) > context->radiusSquared) return 1;
    if (context->count < UINT32_MAX) context->count++;
    return 1;
}

int client_count_visible_units_in_range(ClientObjectGuid centerGuid,
                                         ClientUnitRelationship relationship,
                                         float radius, uint32_t *count) {
    ActivePlayerObjectFunction getActivePlayerObject =
        (ActivePlayerObjectFunction)CLNT_OBJ_MGR_GET_ACTIVE_PLAYER_OBJ;
    EnumerateVisibleObjectsFunction enumerateVisibleObjects =
        (EnumerateVisibleObjectsFunction)ENUM_VISIBLE_OBJECTS;
    UnitRangeCountContext context;
    if (!count || relationship >= CLIENT_UNIT_RELATIONSHIP_COUNT ||
        !(radius >= 0.0f) || radius > FLT_MAX) return 0;
    context.activePlayerObject = getActivePlayerObject();
    if (!context.activePlayerObject ||
        !client_find_object(centerGuid, CLIENT_UNIT_TYPE_MASK, &context.centerObject) ||
        !client_unit_is_living(context.centerObject) ||
        !client_read_object_position(context.centerObject, &context.centerPosition)) return 0;
    context.relationship = relationship;
    context.radiusSquared = (double)radius * (double)radius;
    context.count = 0;
    enumerateVisibleObjects(count_visible_unit, (uintptr_t)&context);
    *count = context.count;
    return 1;
}

int client_trace_line_of_sight(ClientWorldPosition start, ClientWorldPosition end,
                               float startScale, float endScale) {
    TraceLineFunction traceLine = (TraceLineFunction)TRACE_LINE;
    float startCoordinates[3] = { start.x, start.y, start.z + EYE_HEIGHT_PER_SCALE * startScale };
    float endCoordinates[3] = { end.x, end.y, end.z + EYE_HEIGHT_PER_SCALE * endScale };
    float traceHitCoordinates[3] = { 0.0f, 0.0f, 0.0f };
    float traceDistance = 1.0f;
    return traceLine(startCoordinates, endCoordinates, traceHitCoordinates, &traceDistance, LINE_OF_SIGHT_FLAGS, 0) == 0;
}

int client_handle_terrain_click(const ClientTerrainClick *terrainClick) {
    HandleTerrainClickFunction handleTerrainClick = (HandleTerrainClickFunction)SPELL_C__HANDLE_TERRAIN_CLICK;
    if (!*(volatile uintptr_t *)PENDING_SPELL) return 0;
    return handleTerrainClick((void *)terrainClick);
}
