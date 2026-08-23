#include <string.h>

#include "target_selector.h"

static int guid_is_zero(ClientObjectGuid guid) {
    return guid.low == 0 && guid.high == 0;
}

static int guid_equal(ClientObjectGuid first, ClientObjectGuid second) {
    return first.low == second.low && first.high == second.high;
}

static int target_is_current(ClientObjectGuid guid, ClientObjectGuid currentTarget) {
    return !guid_is_zero(currentTarget) && guid_equal(guid, currentTarget);
}

static int compare_unsigned(uint64_t first, uint64_t second) {
    if (first < second) return -1;
    if (first > second) return 1;
    return 0;
}

static int compare_double(double first, double second) {
    if (first < second) return -1;
    if (first > second) return 1;
    return 0;
}

static int compare_health_percent(const ClientTargetCandidate *first,
                                  const ClientTargetCandidate *second) {
    uint64_t firstProduct = (uint64_t)first->health * (uint64_t)second->maxHealth;
    uint64_t secondProduct = (uint64_t)second->health * (uint64_t)first->maxHealth;
    return compare_unsigned(firstProduct, secondProduct);
}

static int compare_missing_health(const ClientTargetCandidate *first,
                                  const ClientTargetCandidate *second) {
    uint32_t firstMissing = first->maxHealth > first->health
        ? first->maxHealth - first->health : 0;
    uint32_t secondMissing = second->maxHealth > second->health
        ? second->maxHealth - second->health : 0;
    return compare_unsigned((uint64_t)secondMissing, (uint64_t)firstMissing);
}

static int compare_guid(const ClientObjectGuid *first, const ClientObjectGuid *second) {
    int comparison = compare_unsigned((uint64_t)first->high, (uint64_t)second->high);
    if (comparison != 0) return comparison;
    return compare_unsigned((uint64_t)first->low, (uint64_t)second->low);
}

int client_target_candidate_before(const ClientTargetCandidate *first,
                                   const ClientTargetCandidate *second,
                                   ClientTargetCriterion criterion,
                                   ClientObjectGuid currentTarget) {
    int firstCurrent;
    int secondCurrent;
    int comparison;

    if (!first || !second || criterion >= CLIENT_TARGET_CRITERION_COUNT) return 0;

    switch (criterion) {
    case CLIENT_TARGET_LOWEST_HEALTH_PERCENT:
        comparison = compare_health_percent(first, second);
        break;
    case CLIENT_TARGET_HIGHEST_HEALTH_PERCENT:
        comparison = -compare_health_percent(first, second);
        break;
    case CLIENT_TARGET_MOST_MISSING_HEALTH:
        comparison = compare_missing_health(first, second);
        break;
    case CLIENT_TARGET_CLOSEST:
        comparison = compare_double(first->distanceSquared, second->distanceSquared);
        break;
    case CLIENT_TARGET_FARTHEST:
        comparison = -compare_double(first->distanceSquared, second->distanceSquared);
        break;
    default:
        return 0;
    }
    if (comparison != 0) return comparison < 0;
    firstCurrent = target_is_current(first->guid, currentTarget);
    secondCurrent = target_is_current(second->guid, currentTarget);
    if (firstCurrent != secondCurrent) return firstCurrent ? 1 : 0;
    return compare_guid(&first->guid, &second->guid) < 0;
}

int client_target_selector_consider(ClientTargetCandidate *candidates,
                                    size_t capacity,
                                    size_t *count,
                                    const ClientTargetCandidate *candidate,
                                    ClientTargetCriterion criterion,
                                    ClientObjectGuid currentTarget) {
    size_t insertionIndex;

    if (!candidates || !count || !candidate || capacity == 0 ||
        *count > capacity || criterion >= CLIENT_TARGET_CRITERION_COUNT) return 0;
    insertionIndex = 0;
    while (insertionIndex < *count &&
           !client_target_candidate_before(candidate, &candidates[insertionIndex],
                                           criterion, currentTarget)) {
        insertionIndex++;
    }
    if (insertionIndex == *count && *count == capacity) return 0;
    if (*count < capacity) (*count)++;
    if (insertionIndex < *count - 1) {
        memmove(&candidates[insertionIndex + 1], &candidates[insertionIndex],
                (*count - insertionIndex - 1) * sizeof(*candidates));
    }
    candidates[insertionIndex] = *candidate;
    return 1;
}
