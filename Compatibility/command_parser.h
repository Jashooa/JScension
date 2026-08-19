#ifndef COMPATIBILITY_COMMAND_PARSER_H
#define COMPATIBILITY_COMMAND_PARSER_H

#include <stddef.h>
#include "client_api.h"

typedef struct {
    const char *cursor;
    const char *end;
} CommandInput;

void command_input_init(CommandInput *input, const char *text, size_t length);
int command_input_matches_prefix(const char *text, size_t length, const char *prefix,
                                 CommandInput *input);
int command_input_parse_guid(CommandInput *input, ClientObjectGuid *guid);
int command_input_parse_float(CommandInput *input, float *value);
int command_input_finished(CommandInput *input);

#endif /* COMPATIBILITY_COMMAND_PARSER_H */
