#ifndef COMPATIBILITY_LOS_GEOMETRY_H
#define COMPATIBILITY_LOS_GEOMETRY_H

#include "client_api.h"

/* Calculates the near-side contact point used for a creature LOS endpoint. */
int client_compute_los_contact_point(ClientWorldPosition casterPoint,
                                     ClientWorldPosition targetPoint,
                                     float combatReach,
                                     ClientWorldPosition *contactPoint);

#endif /* COMPATIBILITY_LOS_GEOMETRY_H */
