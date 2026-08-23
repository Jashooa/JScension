#include <float.h>
#include <string.h>
#include "command_parser.h"

#define MAX_GUID_HEX_DIGITS 16u

static void skip_spaces(CommandInput *input) {
    while (input->cursor < input->end && *input->cursor == ' ') input->cursor++;
}

static int hexadecimal_digit(char character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    if (character >= 'A' && character <= 'F') return character - 'A' + 10;
    return -1;
}

void command_input_init(CommandInput *input, const char *text, size_t length) {
    input->cursor = text;
    input->end = text + length;
}

int command_input_matches_prefix(const char *text, size_t length, const char *prefix,
                                 CommandInput *input) {
    size_t prefixLength = strlen(prefix);
    if (!text || length < prefixLength || memcmp(text, prefix, prefixLength) != 0) return 0;
    command_input_init(input, text + prefixLength, length - prefixLength);
    return 1;
}

int command_input_parse_guid(CommandInput *input, ClientObjectGuid *guid) {
    unsigned long long value = 0;
    unsigned int digits = 0;
    int digit;
    skip_spaces(input);
    if (input->end - input->cursor >= 2 && input->cursor[0] == '0' &&
        (input->cursor[1] == 'x' || input->cursor[1] == 'X')) input->cursor += 2;
    while (input->cursor < input->end && (digit = hexadecimal_digit(*input->cursor)) >= 0) {
        if (digits == MAX_GUID_HEX_DIGITS) return 0;
        value = (value << 4) | (unsigned long long)digit;
        input->cursor++;
        digits++;
    }
    if (digits == 0) return 0;
    guid->low = (unsigned int)value;
    guid->high = (unsigned int)(value >> 32);
    return 1;
}

int command_input_parse_uint32(CommandInput *input, uint32_t *value) {
    uint64_t number = 0;
    unsigned int digits = 0;
    skip_spaces(input);
    while (input->cursor < input->end &&
           *input->cursor >= '0' && *input->cursor <= '9') {
        uint32_t digit = (uint32_t)(*input->cursor - '0');
        if (number > (UINT32_MAX - digit) / 10u) return 0;
        number = number * 10u + digit;
        input->cursor++;
        digits++;
    }
    if (digits == 0) return 0;
    *value = (uint32_t)number;
    return 1;
}

int command_input_parse_float(CommandInput *input, float *value) {
    double number = 0.0;
    double fractionalScale = 0.1;
    int negative = 0;
    int digits = 0;
    skip_spaces(input);
    if (input->cursor < input->end && (*input->cursor == '-' || *input->cursor == '+')) {
        negative = *input->cursor == '-';
        input->cursor++;
    }
    while (input->cursor < input->end && *input->cursor >= '0' && *input->cursor <= '9') {
        number = number * 10.0 + (*input->cursor++ - '0');
        if (number > FLT_MAX) return 0;
        digits++;
    }
    if (input->cursor < input->end && *input->cursor == '.') {
        input->cursor++;
        while (input->cursor < input->end && *input->cursor >= '0' && *input->cursor <= '9') {
            number += (*input->cursor++ - '0') * fractionalScale;
            fractionalScale *= 0.1;
            digits++;
        }
    }
    if (digits == 0 || number > FLT_MAX) return 0;
    *value = negative ? (float)-number : (float)number;
    return 1;
}

int command_input_finished(CommandInput *input) {
    skip_spaces(input);
    return input->cursor == input->end;
}
