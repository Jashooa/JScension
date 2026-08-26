#ifndef COMPATIBILITY_CLIENT_API_H
#define COMPATIBILITY_CLIENT_API_H

#include <stdint.h>
#include <stddef.h>
#define CLIENT_UNIT_TYPE_MASK 0x08u
#define CLIENT_PLAYER_TYPE_MASK 0x10u
#define CLIENT_UNIT_OR_PLAYER_TYPE_MASK (CLIENT_UNIT_TYPE_MASK | CLIENT_PLAYER_TYPE_MASK)
#define CLIENT_OBJECT_FIELD_TYPE_INDEX 0x2u
#define CLIENT_UNIT_FIELD_HEALTH_INDEX 0x18u
#define CLIENT_UNIT_FIELD_MAXHEALTH_INDEX 0x20u
#define CLIENT_UNIT_FIELD_COMBAT_REACH_INDEX 0x42u

struct ClientTargetCandidate;

typedef struct {
    uint32_t low;
    uint32_t high;
} ClientObjectGuid;

typedef enum {
    CLIENT_UNIT_RELATIONSHIP_ANY = 0,
    CLIENT_UNIT_RELATIONSHIP_ENEMY = 1,
    CLIENT_UNIT_RELATIONSHIP_FRIENDLY = 2,
    CLIENT_UNIT_RELATIONSHIP_PLAYER = 3,
    CLIENT_UNIT_RELATIONSHIP_COUNT
} ClientUnitRelationship;

typedef struct {
    float x;
    float y;
    float z;
} ClientWorldPosition;

typedef struct {
    ClientObjectGuid targetGuid;
    ClientWorldPosition location;
} ClientTerrainClick;

int client_find_object(ClientObjectGuid guid, uint32_t typeMask, void **object);
int client_count_visible_units_in_range(ClientObjectGuid centerGuid,
                                         ClientUnitRelationship relationship,
                                         float radius, uint32_t *count);
int client_read_object_position(void *object, ClientWorldPosition *position);
int client_read_object_scale(void *object, float *scale);
int client_trace_line_of_sight(ClientObjectGuid sourceGuid, ClientObjectGuid targetGuid);
int client_handle_terrain_click(const ClientTerrainClick *terrainClick);
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
                                size_t *count);

#endif /* COMPATIBILITY_CLIENT_API_H */
