#ifndef COMPATIBILITY_CLIENT_API_H
#define COMPATIBILITY_CLIENT_API_H

#include <stdint.h>
#define CLIENT_UNIT_TYPE_MASK 0x08u


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
int client_trace_line_of_sight(ClientWorldPosition start, ClientWorldPosition end,
                               float startScale, float endScale);
int client_handle_terrain_click(const ClientTerrainClick *terrainClick);

#endif /* COMPATIBILITY_CLIENT_API_H */
