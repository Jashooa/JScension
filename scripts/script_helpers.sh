#!/usr/bin/env bash
# Shared setup and validation helpers for repository scripts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOLUTION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$SCRIPT_DIR/config.sh"

load_config() {
    if [[ ! -r "$CONFIG_PATH" ]]; then
        printf 'error: missing local configuration: %s\n' "$CONFIG_PATH" >&2
        printf '       copy %s to %s and edit the machine-specific values\n' \
            "$SCRIPT_DIR/config.example.sh" "$CONFIG_PATH" >&2
        return 1
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_PATH"
}

require_config_value() {
    local value_name="$1"

    if [[ -z "${!value_name:-}" ]]; then
        printf 'error: configuration value %s is empty\n' "$value_name" >&2
        return 1
    fi
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$command_name" >&2
        return 1
    fi
}

require_executable() {
    local executable_path="$1"

    if [[ "$executable_path" == */* ]]; then
        if [[ ! -x "$executable_path" ]]; then
            printf 'error: executable not found or not executable: %s\n' "$executable_path" >&2
            return 1
        fi
        return 0
    fi

    require_command "$executable_path"
}

require_directory() {
    local directory_path="$1"

    if [[ ! -d "$directory_path" ]]; then
        printf 'error: directory not found: %s\n' "$directory_path" >&2
        return 1
    fi
}

require_file() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        printf 'error: file not found: %s\n' "$file_path" >&2
        return 1
    fi
}
