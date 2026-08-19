#ifndef COMPATIBILITY_TRUST_MANIFEST_H
#define COMPATIBILITY_TRUST_MANIFEST_H

#include <stddef.h>
#include <stdint.h>

int trust_manifest_choose_owner(uintptr_t manifest, char *ownerName, size_t ownerNameCapacity,
                                void (*log_message)(const char *format, ...));

#endif /* COMPATIBILITY_TRUST_MANIFEST_H */
