#include <float.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "command_parser.h"
#include "target_selector.h"
#include "los_geometry.h"
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
static ClientTargetCandidate target_candidate(uint32_t id,
                                              uint32_t health,
                                              uint32_t maxHealth,
                                              double distanceSquared) {
    ClientTargetCandidate candidate = {{id, 0}, UINT32_MAX, health, maxHealth, distanceSquared};
    return candidate;
}

static void expect_order(const ClientTargetCandidate *candidates,
                         size_t count,
                         uint32_t first,
                         uint32_t second,
                         const char *name) {
    expect_true(count == 2 && candidates[0].guid.low == first &&
                candidates[1].guid.low == second, name);
}

static void test_target_ranking(void) {
    ClientTargetCandidate candidates[CLIENT_TARGET_MAX_RESULTS];
    ClientTargetCandidate candidate;
    ClientObjectGuid noCurrent = {0, 0};
    size_t count = 0;
    size_t index;

    candidate = target_candidate(2, 20, 100, 4.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_LOWEST_HEALTH_PERCENT, noCurrent);
    candidate = target_candidate(1, 50, 100, 1.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_LOWEST_HEALTH_PERCENT, noCurrent);
    expect_order(candidates, count, 2, 1, "lowest health percentage orders candidates");

    count = 0;
    candidate = target_candidate(1, 50, 100, 1.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_HIGHEST_HEALTH_PERCENT, noCurrent);
    candidate = target_candidate(2, 20, 100, 4.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_HIGHEST_HEALTH_PERCENT, noCurrent);
    expect_order(candidates, count, 1, 2, "highest health percentage orders candidates");

    count = 0;
    candidate = target_candidate(1, 90, 100, 1.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_MOST_MISSING_HEALTH, noCurrent);
    candidate = target_candidate(2, 20, 100, 4.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_MOST_MISSING_HEALTH, noCurrent);
    expect_order(candidates, count, 2, 1, "missing health orders candidates");

    count = 0;
    candidate = target_candidate(1, 50, 100, 4.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_CLOSEST, noCurrent);
    candidate = target_candidate(2, 50, 100, 1.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_CLOSEST, noCurrent);
    expect_order(candidates, count, 2, 1, "closest orders candidates");

    count = 0;
    candidate = target_candidate(1, 50, 100, 1.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_FARTHEST, noCurrent);
    candidate = target_candidate(2, 50, 100, 4.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_FARTHEST, noCurrent);
    expect_order(candidates, count, 2, 1, "farthest orders candidates");

    count = 0;
    candidate = target_candidate(2, 90, 100, 1.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_LOWEST_HEALTH_PERCENT,
                                    (ClientObjectGuid){2, 0});
    candidate = target_candidate(1, 90, 100, 1.0);
    client_target_selector_consider(candidates, 64, &count, &candidate,
                                    CLIENT_TARGET_LOWEST_HEALTH_PERCENT,
                                    (ClientObjectGuid){2, 0});
    expect_true(count == 2 && candidates[0].guid.low == 2,
                "current target wins ties and ranking");

    count = 0;
    for (index = 0; index < CLIENT_TARGET_MAX_RESULTS + 1; index++) {
        candidate = target_candidate((uint32_t)(index + 1), 100, 100,
                                     (double)(index + 1));
        client_target_selector_consider(candidates, CLIENT_TARGET_MAX_RESULTS,
                                        &count, &candidate, CLIENT_TARGET_CLOSEST,
                                        noCurrent);
    }
    expect_true(count == CLIENT_TARGET_MAX_RESULTS &&
                candidates[CLIENT_TARGET_MAX_RESULTS - 1].guid.low == 64,
                "ranking keeps a bounded top-64 result set");
    candidate = target_candidate(1000, 1, 100, 0.5);
    client_target_selector_consider(candidates, CLIENT_TARGET_MAX_RESULTS,
                                    &count, &candidate, CLIENT_TARGET_CLOSEST,
                                    noCurrent);
    expect_true(count == CLIENT_TARGET_MAX_RESULTS && candidates[0].guid.low == 1000,
                "bounded ranking inserts a better late candidate");
}


static void expect_point(ClientWorldPosition actual, ClientWorldPosition expected,
                         const char *name) {
    expect_true(fabsf(actual.x - expected.x) < 0.0001f &&
                fabsf(actual.y - expected.y) < 0.0001f &&
                fabsf(actual.z - expected.z) < 0.0001f, name);
}

static void test_los_contact_point(void) {
    ClientWorldPosition contact;

    expect_true(client_compute_los_contact_point((ClientWorldPosition){10.0f, 0.0f, 0.0f},
                                                 (ClientWorldPosition){0.0f, 0.0f, 0.0f},
                                                 3.0f, &contact),
                "LOS contact point accepts a valid reach");
    expect_point(contact, (ClientWorldPosition){3.0f, 0.0f, 0.0f},
                  "LOS contact point stops at combat reach");

    expect_true(client_compute_los_contact_point((ClientWorldPosition){10.0f, 0.0f, 0.0f},
                                                 (ClientWorldPosition){0.0f, 0.0f, 0.0f},
                                                 20.0f, &contact),
                "LOS contact point accepts reach beyond distance");
    expect_point(contact, (ClientWorldPosition){10.0f, 0.0f, 0.0f},
                  "LOS contact point clamps reach to distance");

    expect_true(client_compute_los_contact_point((ClientWorldPosition){1.0f, 2.0f, 3.0f},
                                                 (ClientWorldPosition){1.0f, 2.0f, 3.0f},
                                                 4.0f, &contact),
                "LOS contact point accepts coincident points");
    expect_point(contact, (ClientWorldPosition){1.0f, 2.0f, 3.0f},
                  "LOS contact point preserves coincident target");

    expect_true(!client_compute_los_contact_point((ClientWorldPosition){1.0f, 0.0f, 0.0f},
                                                  (ClientWorldPosition){0.0f, 0.0f, 0.0f},
                                                  -1.0f, &contact),
                "LOS contact point rejects negative reach");
}


int main(void) {
    test_guid_parsing();
    test_uint32_parsing();
    test_float_parsing();
    test_prefix_matching();
    test_target_ranking();
    test_los_contact_point();
    if (failures != 0) {
        fprintf(stderr, "%d native contract test(s) failed\n", failures);
        return 1;
    }
    puts("native contract tests passed");
    return 0;
}
