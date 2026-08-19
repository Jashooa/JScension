#ifndef COMPATIBILITY_SECURE_EXECUTOR_H
#define COMPATIBILITY_SECURE_EXECUTOR_H

#include <stddef.h>

void secure_executor_run(const char *script, size_t length, const char *ownerName);

#endif /* COMPATIBILITY_SECURE_EXECUTOR_H */
