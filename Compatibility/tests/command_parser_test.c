#include <float.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "command_parser.h"

static int failures;

static void expect_true(int condition, const char *name) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", name);
        failures++;
    }
}

static void expect_guid(const char *text, ClientObjectGuid expected, const char *name) {
    CommandInput input;
    ClientObjectGuid actual = {0, 0};
    command_input_init(&input, text, strlen(text));
    expect_true(command_input_parse_guid(&input, &actual), name);
    expect_true(actual.low == expected.low && actual.high == expected.high, name);
    expect_true(command_input_finished(&input), name);
}

static void test_guid_parsing(void) {
    CommandInput input;
    ClientObjectGuid guid;

    expect_guid("0x1234567890abcdef", (ClientObjectGuid){0x90abcdefu, 0x12345678u},
                "GUID accepts hexadecimal prefix and 64-bit values");
    expect_guid(" ABCD ", (ClientObjectGuid){0x0000abcdu, 0x00000000u},
                "GUID accepts surrounding spaces");

    command_input_init(&input, "1234567890abcdef0", 17);
    expect_true(!command_input_parse_guid(&input, &guid), "GUID rejects more than 64 bits");

    command_input_init(&input, "0x", 2);
    expect_true(!command_input_parse_guid(&input, &guid), "GUID rejects an empty value");

    command_input_init(&input, "12zz", 4);
    expect_true(command_input_parse_guid(&input, &guid), "GUID parses the valid prefix");
    expect_true(!command_input_finished(&input), "GUID caller detects trailing invalid text");
}
static void expect_uint32(const char *text, uint32_t expected, const char *name) {
    CommandInput input;
    uint32_t actual = 0;
    command_input_init(&input, text, strlen(text));
    expect_true(command_input_parse_uint32(&input, &actual), name);
    expect_true(actual == expected, name);
    expect_true(command_input_finished(&input), name);
}

static void test_uint32_parsing(void) {
    CommandInput input;
    uint32_t value;

    expect_uint32(" 0 ", 0u, "uint32 accepts zero");
    expect_uint32("3", 3u, "uint32 accepts the player relationship code");
    expect_uint32("4294967295", UINT32_MAX, "uint32 accepts the maximum value");

    command_input_init(&input, "-1", 2);
    expect_true(!command_input_parse_uint32(&input, &value), "uint32 rejects a negative sign");
    command_input_init(&input, "+1", 2);
    expect_true(!command_input_parse_uint32(&input, &value), "uint32 rejects a positive sign");
    command_input_init(&input, "abc", 3);
    expect_true(!command_input_parse_uint32(&input, &value), "uint32 rejects alphabetic input");
    command_input_init(&input, "4294967296", 10);
    expect_true(!command_input_parse_uint32(&input, &value), "uint32 rejects overflow");
    command_input_init(&input, "1.0", 3);
    expect_true(command_input_parse_uint32(&input, &value), "uint32 parses the decimal prefix");
    expect_true(!command_input_finished(&input), "uint32 caller detects fractional text");
    command_input_init(&input, "12abc", 5);
    expect_true(command_input_parse_uint32(&input, &value), "uint32 parses the numeric prefix");
    expect_true(!command_input_finished(&input), "uint32 caller detects alphabetic suffix");
}

static void expect_float(const char *text, float expected, const char *name) {
    CommandInput input;
    float actual = 0.0f;
    command_input_init(&input, text, strlen(text));
    expect_true(command_input_parse_float(&input, &actual), name);
    expect_true(fabsf(actual - expected) < 0.0001f, name);
    expect_true(command_input_finished(&input), name);
}

static void test_float_parsing(void) {
    CommandInput input;
    float value;

    expect_float(" -12.5 ", -12.5f, "float accepts sign and fractional value");
    expect_float("+7", 7.0f, "float accepts a positive sign");
    expect_float(".25", 0.25f, "float accepts a leading decimal point");
    expect_float("5.", 5.0f, "float accepts a trailing decimal point");

    command_input_init(&input, "-", 1);
    expect_true(!command_input_parse_float(&input, &value), "float rejects a sign without digits");

    command_input_init(&input, "1e3", 3);
    expect_true(command_input_parse_float(&input, &value), "float parses the decimal prefix");
    expect_true(!command_input_finished(&input), "float caller detects exponent text");

    command_input_init(&input, "9999999999999999999999999999999999999999", 40);
    expect_true(!command_input_parse_float(&input, &value), "float rejects values above FLT_MAX");
}

static void test_prefix_matching(void) {
    CommandInput input;

    expect_true(command_input_matches_prefix("Command value", 13, "Command ", &input),
                "prefix matcher accepts a matching command");
    expect_true(input.cursor == input.end - 5, "prefix matcher positions the argument cursor");
    expect_true(!command_input_finished(&input), "prefix matcher leaves arguments available");
    expect_true(!command_input_matches_prefix("Command", 7, "Command ", &input),
                "prefix matcher rejects a missing argument");
    expect_true(!command_input_matches_prefix("Other value", 11, "Command ", &input),
                "prefix matcher rejects an unrelated command");
}

int main(void) {
    test_guid_parsing();
    test_uint32_parsing();

    test_float_parsing();
    test_prefix_matching();
    if (failures != 0) {
        fprintf(stderr, "%d native contract test(s) failed\n", failures);
        return 1;
    }
    puts("native contract tests passed");
    return 0;
}
