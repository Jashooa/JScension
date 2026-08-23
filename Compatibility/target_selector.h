#ifndef COMPATIBILITY_TARGET_SELECTOR_H
#define COMPATIBILITY_TARGET_SELECTOR_H

#include <stddef.h>
#include <stdint.h>

#include "client_api.h"

#define CLIENT_TARGET_MAX_RESULTS 64u
#define CLIENT_TARGET_MAX_FILTER_GUIDS 64u

typedef enum {
    CLIENT_TARGET_LOWEST_HEALTH_PERCENT = 0,
    CLIENT_TARGET_HIGHEST_HEALTH_PERCENT = 1,
    CLIENT_TARGET_MOST_MISSING_HEALTH = 2,
    CLIENT_TARGET_CLOSEST = 3,
    CLIENT_TARGET_FARTHEST = 4,
    CLIENT_TARGET_CRITERION_COUNT
} ClientTargetCriterion;

typedef enum {
    CLIENT_TARGET_ENEMY = 0,
    CLIENT_TARGET_ENEMY_PLAYER = 1,
    CLIENT_TARGET_ENEMY_NPC = 2,
    CLIENT_TARGET_FRIENDLY_PLAYER = 3,
    CLIENT_TARGET_CATEGORY_COUNT
} ClientTargetCategory;

typedef struct ClientTargetCandidate {
    ClientObjectGuid guid;
    uint32_t allowedIndex;
    uint32_t health;
    uint32_t maxHealth;
    double distanceSquared;
} ClientTargetCandidate;

int client_target_candidate_before(const ClientTargetCandidate *first,
                                   const ClientTargetCandidate *second,
                                   ClientTargetCriterion criterion,
                                   ClientObjectGuid currentTarget);

int client_target_selector_consider(ClientTargetCandidate *candidates,
                                    size_t capacity,
                                    size_t *count,
                                    const ClientTargetCandidate *candidate,
                                    ClientTargetCriterion criterion,
                                    ClientObjectGuid currentTarget);

#endif /* COMPATIBILITY_TARGET_SELECTOR_H */
