#include <float.h>
#include <windows.h>
#include "client_api.h"
#include "client_layout.h"
#include "target_selector.h"
#define OBJECT_GUID_OFFSET 0x30u
#define OBJECT_POSITION_LINK_OFFSET 0xd8u
#define OBJECT_POSITION_OFFSET 0x10u
#define OBJECT_DESCRIPTOR_SCAN_END 0x40u
#define OBJECT_FIELD_TYPE_OFFSET (CLIENT_OBJECT_FIELD_TYPE_INDEX * sizeof(uint32_t))
#define OBJECT_FIELD_SCALE_INDEX 0x4u
#define OBJECT_FIELD_SCALE_OFFSET (OBJECT_FIELD_SCALE_INDEX * sizeof(uint32_t))
#define UNIT_FIELD_HEALTH_OFFSET (CLIENT_UNIT_FIELD_HEALTH_INDEX * sizeof(uint32_t))
#define UNIT_FIELD_MAXHEALTH_OFFSET (CLIENT_UNIT_FIELD_MAXHEALTH_INDEX * sizeof(uint32_t))
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
typedef struct {
    void *activePlayerObject;
    ClientWorldPosition centerPosition;
    float centerScale;
    ClientTargetCategory category;
    ClientTargetCriterion criterion;
    double radiusSquared;
    ClientObjectGuid currentTarget;
    const ClientObjectGuid *allowed;
    size_t allowedCount;
    const ClientObjectGuid *excluded;
    size_t excludedCount;
    ClientTargetCandidate *candidates;
    size_t capacity;
    size_t count;
} TargetSelectionContext;
static int client_read_object_type(void *object, uint32_t *type) {
    return client_read_object_field(object, OBJECT_FIELD_TYPE_OFFSET, type);
}

static int client_read_object_max_health(void *object, uint32_t *maxHealth) {
    return client_read_object_field(object, UNIT_FIELD_MAXHEALTH_OFFSET, maxHealth);
}
static int client_guid_equal(ClientObjectGuid first, ClientObjectGuid second) {
    return first.low == second.low && first.high == second.high;
}


static int client_guid_in_list(ClientObjectGuid guid,
                               const ClientObjectGuid *list,
                               size_t count,
                               size_t *index) {
    size_t listIndex;
    if (!list) return 0;
    for (listIndex = 0; listIndex < count; listIndex++) {
        if (client_guid_equal(guid, list[listIndex])) {
            if (index) *index = listIndex;
            return 1;
        }
    }
    return 0;
}

static int target_category_matches(TargetSelectionContext *context,
                                   ClientObjectGuid guid,
                                   void *candidate,
                                   uint32_t objectType,
                                   uint32_t *allowedIndex) {
    UnitCanAssistFunction canAssist;
    UnitCanAttackFunction canAttack;
    int isPlayer = (objectType & CLIENT_PLAYER_TYPE_MASK) != 0;
    int isUnit = (objectType & CLIENT_UNIT_TYPE_MASK) != 0;
    size_t listIndex = 0;

    if (!isUnit && !isPlayer) return 0;
    switch (context->category) {
    case CLIENT_TARGET_ENEMY:
        canAttack = (UnitCanAttackFunction)CGUNIT_C__CAN_ATTACK;
        return canAttack(context->activePlayerObject, candidate) != 0;
    case CLIENT_TARGET_ENEMY_PLAYER:
        if (!isPlayer) return 0;
        canAttack = (UnitCanAttackFunction)CGUNIT_C__CAN_ATTACK;
        return canAttack(context->activePlayerObject, candidate) != 0;
    case CLIENT_TARGET_ENEMY_NPC:
        if (!isUnit || isPlayer) return 0;
        canAttack = (UnitCanAttackFunction)CGUNIT_C__CAN_ATTACK;
        return canAttack(context->activePlayerObject, candidate) != 0;
    case CLIENT_TARGET_FRIENDLY_PLAYER:
        if (!isPlayer ||
            !client_guid_in_list(guid, context->allowed, context->allowedCount, &listIndex)) return 0;
        if (candidate != context->activePlayerObject) {
            canAssist = (UnitCanAssistFunction)CGUNIT_C__CAN_ASSIST;
            if (!canAssist(context->activePlayerObject, candidate, 0)) return 0;
        }
        *allowedIndex = (uint32_t)listIndex;
        return 1;
    default:
        return 0;
    }
}

static int select_visible_unit(uint32_t low, uint32_t high, uintptr_t contextAddress) {
    TargetSelectionContext *context = (TargetSelectionContext *)contextAddress;
    ClientObjectGuid guid = { low, high };
    ClientTargetCandidate candidate;
    ClientWorldPosition position;
    void *object;
    uint32_t objectType;
    uint32_t health;
    uint32_t maxHealth;
    uint32_t allowedIndex = UINT32_MAX;
    float endScale;
    double distanceSquared;
    if (client_guid_in_list(guid, context->excluded, context->excludedCount, NULL) ||
        !client_find_object(guid, CLIENT_UNIT_OR_PLAYER_TYPE_MASK, &object) ||
        (object == context->activePlayerObject &&
         context->category != CLIENT_TARGET_FRIENDLY_PLAYER) ||
        !client_unit_is_living(object) ||
        !client_read_object_type(object, &objectType) ||
        !target_category_matches(context, guid, object, objectType, &allowedIndex) ||
        !client_read_object_health(object, &health) ||
        !client_read_object_max_health(object, &maxHealth) ||
        maxHealth == 0 ||
        !client_read_object_position(object, &position)) return 1;

    distanceSquared = squared_distance(context->centerPosition, position);
    if (distanceSquared > context->radiusSquared ||
        !client_read_object_scale(object, &endScale) ||
        !client_trace_line_of_sight(context->centerPosition, position,
                                     context->centerScale, endScale)) return 1;
    candidate.guid = guid;
    candidate.allowedIndex = allowedIndex;
    candidate.health = health;
    candidate.maxHealth = maxHealth;
    candidate.distanceSquared = distanceSquared;
    client_target_selector_consider(context->candidates, context->capacity,
                                     &context->count, &candidate,
                                     context->criterion, context->currentTarget);
    return 1;
}

int client_select_visible_units(unsigned int category,
                                unsigned int criterion,
                                float maxDistance,
                                ClientObjectGuid currentTarget,
                                const ClientObjectGuid *allowed,
                                size_t allowedCount,
                                const ClientObjectGuid *excluded,
                                size_t excludedCount,
                                struct ClientTargetCandidate *candidates,
                                size_t capacity,
                                size_t *count) {
    ActivePlayerObjectFunction getActivePlayerObject =
        (ActivePlayerObjectFunction)CLNT_OBJ_MGR_GET_ACTIVE_PLAYER_OBJ;
    EnumerateVisibleObjectsFunction enumerateVisibleObjects =
        (EnumerateVisibleObjectsFunction)ENUM_VISIBLE_OBJECTS;
    TargetSelectionContext context;
    if (!count) return 0;
    *count = 0;
    if (category >= CLIENT_TARGET_CATEGORY_COUNT ||
        criterion >= CLIENT_TARGET_CRITERION_COUNT ||
        !(maxDistance >= 0.0f) || maxDistance > FLT_MAX ||
        !candidates || capacity == 0 || capacity > CLIENT_TARGET_MAX_RESULTS ||
        allowedCount > CLIENT_TARGET_MAX_FILTER_GUIDS ||
        excludedCount > CLIENT_TARGET_MAX_FILTER_GUIDS ||
        (allowedCount > 0 && !allowed) ||
        (excludedCount > 0 && !excluded) ||
        ((category == CLIENT_TARGET_FRIENDLY_PLAYER) != (allowedCount > 0)) ||
        ((category != CLIENT_TARGET_FRIENDLY_PLAYER) && allowedCount != 0)) return 0;
    context.activePlayerObject = getActivePlayerObject();
    if (!context.activePlayerObject ||
        !client_read_object_position(context.activePlayerObject, &context.centerPosition) ||
        !client_read_object_scale(context.activePlayerObject, &context.centerScale)) return 0;
    context.category = (ClientTargetCategory)category;
    context.criterion = (ClientTargetCriterion)criterion;
    context.radiusSquared = (double)maxDistance * (double)maxDistance;
    context.currentTarget = currentTarget;
    context.allowed = allowed;
    context.allowedCount = allowedCount;
    context.excluded = excluded;
    context.excludedCount = excludedCount;
    context.candidates = (ClientTargetCandidate *)candidates;
    context.capacity = capacity;
    context.count = 0;
    enumerateVisibleObjects(select_visible_unit, (uintptr_t)&context);
    *count = context.count;
    return 1;
}
