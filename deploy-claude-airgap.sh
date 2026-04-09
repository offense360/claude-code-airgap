#!/usr/bin/env bash

set -euo pipefail

TOOL_VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANAGED_SETTINGS_TEMPLATE='{
  "env": {
    "DISABLE_AUTOUPDATER": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_NON_ESSENTIAL_MODEL_CALLS": "1",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000",
    "ANTHROPIC_AUTH_TOKEN": "no-token"
  }
}'

show_banner() {
    local mode="$1"
    printf '========================================\n'
    printf 'Claude Code Airgap\n'
    printf '%s\n' "$mode"
    printf '========================================\n'

    if [[ "${CLAUDE_CODE_AIRGAP_BANNER:-0}" == "1" ]]; then
        cat <<'EOF'
   ______ _                 _      
  / ____/ /___ ___  _______(_)___ _
 / /   / / __ `/ / / / ___/ / __ `/
/ /___/ / /_/ / /_/ / /  / / /_/ / 
\____/_/\__,_/\__,_/_/  /_/\__,_/  

EOF
    fi
}

show_help() {
    cat <<'EOF'
deploy-claude-airgap.sh

Usage:
  ./deploy-claude-airgap.sh
  ./deploy-claude-airgap.sh -V
  ./deploy-claude-airgap.sh -h

Options:
  -V, --tool-version  Print tool version.
  -h, --help          Print help.
  -tui                Reserved for a later release. Not available in phase 1.

Supported platform in phase 1:
  linux-x64
EOF
}

require_tools() {
    local tool
    for tool in bash sha256sum awk grep ldd mktemp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'Missing required tool: %s\n' "$tool" >&2
            exit 1
        fi
    done
}

get_current_platform() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        printf 'Only Linux is supported by this script.\n' >&2
        exit 1
    fi

    case "$(uname -m)" in
        x86_64|amd64) ;;
        *)
            printf 'Non-x64 Linux is not supported in phase 1.\n' >&2
            exit 1
            ;;
    esac

    if ldd --version 2>&1 | grep -qi musl; then
        printf 'musl-based Linux is not supported in phase 1.\n' >&2
        exit 1
    fi

    printf 'linux-x64\n'
}

find_bundle_dir() {
    if [[ -f "$SCRIPT_DIR/downloads/VERSION.json" && -f "$SCRIPT_DIR/downloads/manifest.json" ]]; then
        printf '%s\n' "$SCRIPT_DIR/downloads"
        return 0
    fi

    if [[ -f "$SCRIPT_DIR/VERSION.json" && -f "$SCRIPT_DIR/manifest.json" ]]; then
        printf '%s\n' "$SCRIPT_DIR"
        return 0
    fi

    printf 'Unable to locate bundle metadata. Expected VERSION.json and manifest.json either in the script directory or in a downloads subdirectory.\n' >&2
    exit 1
}

binary_file_name() {
    local version="$1"
    local platform="$2"
    case "$platform" in
        win32-*) printf 'claude-%s-%s.exe\n' "$version" "$platform" ;;
        *) printf 'claude-%s-%s\n' "$version" "$platform" ;;
    esac
}

manifest_get_version() {
    local manifest_path="$1"
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest_path" | head -n 1
}

manifest_get_checksum() {
    local manifest_path="$1"
    local platform="$2"
    sed -n "/\"$platform\"[[:space:]]*:/,/}/ s/.*\"checksum\"[[:space:]]*:[[:space:]]*\"\([0-9a-f]*\)\".*/\1/p" "$manifest_path" | head -n 1
}

manifest_get_size() {
    local manifest_path="$1"
    local platform="$2"
    sed -n "/\"$platform\"[[:space:]]*:/,/}/ s/.*\"size\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$manifest_path" | head -n 1
}

version_json_get_string() {
    local file_path="$1"
    local key="$2"
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file_path" | head -n 1
}

version_json_has_platform() {
    local file_path="$1"
    local platform="$2"
    grep -q "\"$platform\"" "$file_path"
}

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

ensure_path_exports() {
    local path_entry="$1"
    mkdir -p "$path_entry"
    export PATH="$path_entry:$PATH"

    local block_start="# >>> claude-code-airgap >>>"
    local block_end="# <<< claude-code-airgap <<<"
    local block="$block_start
export PATH=\"\$HOME/.local/bin:\$PATH\"
$block_end"
    local profile
    for profile in "$HOME/.bashrc" "$HOME/.profile"; do
        if [[ -f "$profile" ]] && grep -Fq "$block_start" "$profile"; then
            continue
        fi
        printf '\n%s\n' "$block" >>"$profile"
    done
}

write_settings_template() {
    local target_path="$1"
    local template_path="$SCRIPT_DIR/settings/settings.json.template"
    local parent_dir
    parent_dir="$(dirname "$target_path")"
    mkdir -p "$parent_dir"

    if [[ -f "$target_path" ]]; then
        if [[ "${CLAUDE_CODE_AIRGAP_REPLACE_SETTINGS:-0}" != "1" ]]; then
            printf 'Existing settings file found at %s. Refusing to overwrite without CLAUDE_CODE_AIRGAP_REPLACE_SETTINGS=1.\n' "$target_path" >&2
            exit 1
        fi
        cp "$target_path" "$target_path.bak.$(date +%Y%m%d%H%M%S)"
    fi

    local tmp
    tmp="$(mktemp "${target_path}.tmp.XXXXXX")"
    if [[ -f "$template_path" ]]; then
        cp "$template_path" "$tmp"
    else
        printf '%s\n' "$MANAGED_SETTINGS_TEMPLATE" >"$tmp"
    fi
    mv "$tmp" "$target_path"
}

run_health_checks() {
    printf 'Running health checks...\n'

    if ! command -v claude >/dev/null 2>&1; then
        printf 'Claude command was not found on PATH after installation.\n' >&2
        exit 1
    fi

    claude --version

    set +e
    claude doctor
    local doctor_exit=$?
    set -e

    if [[ "$doctor_exit" -ne 0 ]]; then
        printf 'Warning: claude doctor returned a non-zero exit code (%s). This does not block deployment.\n' "$doctor_exit" >&2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -V|--tool-version)
            printf '%s\n' "$TOOL_VERSION"
            exit 0
            ;;
        -tui)
            printf 'TUI is deferred in phase 1.\n' >&2
            exit 1
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

require_tools
show_banner "Deploy Offline Bundle"
CURRENT_PLATFORM="$(get_current_platform)"
BUNDLE_DIR="$(find_bundle_dir)"
VERSION_JSON="$BUNDLE_DIR/VERSION.json"
MANIFEST_JSON="$BUNDLE_DIR/manifest.json"
CLAUDE_VERSION="$(version_json_get_string "$VERSION_JSON" "claude_version")"
MANIFEST_VERSION="$(manifest_get_version "$MANIFEST_JSON")"

if [[ -z "$CLAUDE_VERSION" ]]; then
    printf 'VERSION.json does not contain claude_version.\n' >&2
    exit 1
fi

if [[ "$MANIFEST_VERSION" != "$CLAUDE_VERSION" ]]; then
    printf 'Manifest version mismatch. VERSION.json=%s manifest=%s\n' "$CLAUDE_VERSION" "$MANIFEST_VERSION" >&2
    exit 1
fi

if ! version_json_has_platform "$VERSION_JSON" "$CURRENT_PLATFORM"; then
    printf 'The bundle does not include the current platform: %s\n' "$CURRENT_PLATFORM" >&2
    exit 1
fi

EXPECTED_CHECKSUM="$(manifest_get_checksum "$MANIFEST_JSON" "$CURRENT_PLATFORM")"
EXPECTED_SIZE="$(manifest_get_size "$MANIFEST_JSON" "$CURRENT_PLATFORM")"
if [[ -z "$EXPECTED_CHECKSUM" || -z "$EXPECTED_SIZE" ]]; then
    printf 'Manifest data is incomplete for platform %s.\n' "$CURRENT_PLATFORM" >&2
    exit 1
fi

BINARY_PATH="$BUNDLE_DIR/$(binary_file_name "$CLAUDE_VERSION" "$CURRENT_PLATFORM")"
if [[ ! -f "$BINARY_PATH" ]]; then
    printf 'Bundle binary is missing: %s\n' "$BINARY_PATH" >&2
    exit 1
fi

ACTUAL_SIZE="$(wc -c <"$BINARY_PATH" | tr -d ' ')"
if [[ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
    printf 'Binary size mismatch. Expected %s bytes, got %s.\n' "$EXPECTED_SIZE" "$ACTUAL_SIZE" >&2
    exit 1
fi

ACTUAL_HASH="$(hash_file "$BINARY_PATH")"
if [[ "$ACTUAL_HASH" != "$EXPECTED_CHECKSUM" ]]; then
    printf 'Binary checksum mismatch for %s\n' "$BINARY_PATH" >&2
    exit 1
fi

ensure_path_exports "$HOME/.local/bin"
write_settings_template "$HOME/.claude/settings.json"

WORKING_DIRECTORY="${TMPDIR:-/tmp}/claude-code-airgap/$CLAUDE_VERSION"
mkdir -p "$WORKING_DIRECTORY"
WORKING_BINARY="$WORKING_DIRECTORY/$(basename "$BINARY_PATH")"
cp "$BINARY_PATH" "$WORKING_BINARY"
chmod +x "$WORKING_BINARY"

if [[ "${CLAUDE_CODE_AIRGAP_SKIP_INSTALL:-0}" == "1" ]]; then
    printf 'Skipping install because CLAUDE_CODE_AIRGAP_SKIP_INSTALL=1\n'
else
    "$WORKING_BINARY" install
    run_health_checks
fi

printf 'Bundle directory: %s\n' "$BUNDLE_DIR"
printf 'Verified version: %s\n' "$CLAUDE_VERSION"
printf 'PATH entry ensured: %s\n' "$HOME/.local/bin"
printf 'Settings path: %s\n' "$HOME/.claude/settings.json"
