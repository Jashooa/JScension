#include <math.h>
#include "los_geometry.h"

static int finite_point(ClientWorldPosition point) {
    return isfinite(point.x) && isfinite(point.y) && isfinite(point.z);
}

int client_compute_los_contact_point(ClientWorldPosition casterPoint,
                                     ClientWorldPosition targetPoint,
                                     float combatReach,
                                     ClientWorldPosition *contactPoint) {
    float deltaX;
    float deltaY;
    float deltaZ;
    float distanceSquared;
    float distance;
    float offset;
    float factor;

    if (!contactPoint || !finite_point(casterPoint) || !finite_point(targetPoint) ||
        !isfinite(combatReach) || combatReach < 0.0f) return 0;

    *contactPoint = targetPoint;
    deltaX = casterPoint.x - targetPoint.x;
    deltaY = casterPoint.y - targetPoint.y;
    deltaZ = casterPoint.z - targetPoint.z;
    distanceSquared = deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ;
    if (!(distanceSquared > 0.0f) || !isfinite(distanceSquared)) return 1;

    distance = sqrtf(distanceSquared);
    if (!isfinite(distance)) return 0;
    offset = combatReach < distance ? combatReach : distance;
    factor = offset / distance;
    contactPoint->x += deltaX * factor;
    contactPoint->y += deltaY * factor;
    contactPoint->z += deltaZ * factor;
    return 1;
}
