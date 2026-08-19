#include <windows.h>
#include <string.h>
#include "trust_manifest.h"

#define MANIFEST_ENTRY_SIZE 0x1cu
#define STRING_SIZE_OFFSET 0x10u
#define TRUSTED_FLAG_OFFSET 0x18u
#define INLINE_STRING_MAXIMUM 15u
#define MAXIMUM_ENTRY_COUNT 400u
#define MINIMUM_HEAP_ADDRESS 0x10000u
#define BLIZZARD_PREFIX_LENGTH 9u

static int copy_owner(char *destination, size_t capacity, const char *source, size_t length) {
    if (length >= capacity) return 0;
    memcpy(destination, source, length);
    destination[length] = 0;
    return 1;
}

int trust_manifest_choose_owner(uintptr_t manifest, char *ownerName, size_t ownerNameCapacity,
                                void (*log_message)(const char *format, ...)) {
    unsigned char *begin;
    unsigned char *end;
    const char *firstTrusted = NULL;
    size_t firstTrustedLength = 0;
    const char *blizzardTrusted = NULL;
    size_t blizzardTrustedLength = 0;
    size_t count;
    size_t index;
    if (!manifest || !ownerName || ownerNameCapacity == 0) return 0;
    begin = *(unsigned char **)(manifest + 4);
    end = *(unsigned char **)(manifest + 8);
    if (!begin || !end || end < begin) { log_message("owner: manifest vector invalid"); return 0; }
    count = (size_t)(end - begin) / MANIFEST_ENTRY_SIZE;
    if (count == 0 || count > MAXIMUM_ENTRY_COUNT) { log_message("owner: manifest count implausible"); return 0; }
    for (index = 0; index < count; index++) {
        unsigned char *entry = begin + index * MANIFEST_ENTRY_SIZE;
        size_t nameLength;
        const char *name;
        uint32_t trusted;
        if (IsBadReadPtr(entry, MANIFEST_ENTRY_SIZE)) break;
        nameLength = *(uint32_t *)(entry + STRING_SIZE_OFFSET);
        trusted = *(uint32_t *)(entry + TRUSTED_FLAG_OFFSET);
        if (nameLength >= ownerNameCapacity || trusted != 1) continue;
        name = nameLength <= INLINE_STRING_MAXIMUM ? (const char *)entry : *(const char **)entry;
        if ((uintptr_t)name < MINIMUM_HEAP_ADDRESS || IsBadStringPtrA(name, (UINT_PTR)nameLength + 1)) continue;
        if (!firstTrusted) { firstTrusted = name; firstTrustedLength = nameLength; }
        if (strcmp(name, "AscensionUI") == 0) return copy_owner(ownerName, ownerNameCapacity, name, nameLength);
        if (!blizzardTrusted && strncmp(name, "Blizzard_", BLIZZARD_PREFIX_LENGTH) == 0) {
            blizzardTrusted = name;
            blizzardTrustedLength = nameLength;
        }
    }
    if (blizzardTrusted) return copy_owner(ownerName, ownerNameCapacity, blizzardTrusted, blizzardTrustedLength);
    if (firstTrusted) return copy_owner(ownerName, ownerNameCapacity, firstTrusted, firstTrustedLength);
    log_message("owner: no trusted name in manifest");
    return 0;
}
