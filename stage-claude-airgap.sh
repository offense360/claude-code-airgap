#!/usr/bin/env bash

set -euo pipefail

TOOL_VERSION="0.1.0"
RELEASE_BASE_URL="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/downloads"
SUPPORTED_PLATFORMS=("win32-x64" "linux-x64")

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
stage-claude-airgap.sh

Usage:
  ./stage-claude-airgap.sh [-v VERSION] [-p PLATFORM[,PLATFORM]]
  ./stage-claude-airgap.sh -V
  ./stage-claude-airgap.sh -h

Options:
  -v, --version       Claude version to stage. Defaults to latest.
  -p, --platform      Comma-separated platform list or all. Defaults to current platform.
  -V, --tool-version  Print tool version.
  -h, --help          Print help.
  -tui                Reserved for a later release. Not available in phase 1.

Supported platforms in phase 1:
  win32-x64
  linux-x64
EOF
}

require_tools() {
    local tool
    for tool in bash curl sha256sum awk grep mktemp ldd; do
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

validate_version() {
    local version="$1"
    if [[ -z "$version" ]]; then
        return 0
    fi

    if [[ ! "$version" =~ ^(stable|latest|[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9._-]+)?)$ ]]; then
        printf 'Invalid version format: %s\n' "$version" >&2
        exit 1
    fi
}

resolve_version() {
    local requested="$1"
    local channel=""
    if [[ -z "$requested" ]]; then
        channel="latest"
    elif [[ "$requested" == "latest" || "$requested" == "stable" ]]; then
        channel="$requested"
    else
        printf '%s\n' "$requested"
        return 0
    fi

    curl -fsSL "$RELEASE_BASE_URL/$channel"
}

resolve_platforms() {
    local platform_arg="$1"
    local item

    if [[ -z "$platform_arg" ]]; then
        get_current_platform
        return 0
    fi

    if [[ "$platform_arg" == "all" ]]; then
        printf '%s\n' "${SUPPORTED_PLATFORMS[@]}"
        return 0
    fi

    IFS=',' read -r -a requested <<<"$platform_arg"
    for item in "${requested[@]}"; do
        item="${item//[[:space:]]/}"
        if [[ -z "$item" ]]; then
            continue
        fi
        case "$item" in
            win32-x64|linux-x64) printf '%s\n' "$item" ;;
            *)
                printf 'Unsupported platform: %s\n' "$item" >&2
                exit 1
                ;;
        esac
    done
}

binary_leaf_name() {
    case "$1" in
        win32-*) printf 'claude.exe\n' ;;
        *) printf 'claude\n' ;;
    esac
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

write_version_json() {
    local target="$1"
    local resolved_version="$2"
    local manifest_url="$3"
    shift 3
    local platforms=("$@")
    local tmp
    tmp="$(mktemp "${target}.tmp.XXXXXX")"
    {
        printf '{\n'
        printf '  "schema_version": 1,\n'
        printf '  "tool_version": "%s",\n' "$TOOL_VERSION"
        printf '  "claude_version": "%s",\n' "$resolved_version"
        printf '  "download_date_utc": "%s",\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf '  "downloaded_platforms": [\n'
        local idx
        for idx in "${!platforms[@]}"; do
            if [[ "$idx" -gt 0 ]]; then
                printf ',\n'
            fi
            printf '    "%s"' "${platforms[$idx]}"
        done
        printf '\n  ],\n'
        printf '  "source_latest_url": "%s/latest",\n' "$RELEASE_BASE_URL"
        printf '  "source_manifest_url": "%s"\n' "$manifest_url"
        printf '}\n'
    } >"$tmp"
    mv "$tmp" "$target"
}

existing_version_json_version() {
    local version_json_path="$1"
    if [[ ! -f "$version_json_path" ]]; then
        return 0
    fi
    version_json_get_string "$version_json_path" "claude_version"
}

version_json_get_string() {
    local file_path="$1"
    local key="$2"
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file_path" | head -n 1
}

version_json_get_platforms() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        return 0
    fi
    sed -n 's/.*"\([^"]*\)".*/\1/p' "$file_path" | grep -E '^(win32-x64|linux-x64)$' || true
}

download_to_path() {
    local url="$1"
    local target="$2"
    local tmp="${target}.part"
    rm -f "$tmp"
    curl -fsSL "$url" -o "$tmp"
    mv "$tmp" "$target"
}

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

VERSION_ARG=""
PLATFORM_ARG=""

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
        -v|--version)
            VERSION_ARG="${2:-}"
            shift 2
            ;;
        -p|--platform)
            PLATFORM_ARG="${2:-}"
            shift 2
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
show_banner "Stage Offline Bundle"
validate_version "$VERSION_ARG"
CURRENT_PLATFORM="$(get_current_platform)"
RESOLVED_VERSION="$(resolve_version "$VERSION_ARG")"

mkdir -p "$BUNDLE_DIR"
MANIFEST_URL="$RELEASE_BASE_URL/$RESOLVED_VERSION/manifest.json"
MANIFEST_PATH="$BUNDLE_DIR/manifest.json"
VERSION_JSON_PATH="$BUNDLE_DIR/VERSION.json"
EXISTING_VERSION="$(existing_version_json_version "$VERSION_JSON_PATH")"
if [[ -n "$EXISTING_VERSION" && "$EXISTING_VERSION" != "$RESOLVED_VERSION" ]]; then
    printf 'Bundle already contains version %s. Remove the downloads directory before staging version %s.\n' "$EXISTING_VERSION" "$RESOLVED_VERSION" >&2
    exit 1
fi

download_to_path "$MANIFEST_URL" "$MANIFEST_PATH"

MANIFEST_VERSION="$(manifest_get_version "$MANIFEST_PATH")"
if [[ "$MANIFEST_VERSION" != "$RESOLVED_VERSION" ]]; then
    printf 'Manifest version mismatch. Expected %s, got %s.\n' "$RESOLVED_VERSION" "$MANIFEST_VERSION" >&2
    exit 1
fi

mapfile -t SELECTED_PLATFORMS < <(resolve_platforms "$PLATFORM_ARG")
if [[ "${#SELECTED_PLATFORMS[@]}" -eq 0 ]]; then
    printf 'Platform list is empty.\n' >&2
    exit 1
fi

SUCCESSFUL_PLATFORMS=()
for PLATFORM in "${SELECTED_PLATFORMS[@]}"; do
    CHECKSUM="$(manifest_get_checksum "$MANIFEST_PATH" "$PLATFORM")"
    SIZE="$(manifest_get_size "$MANIFEST_PATH" "$PLATFORM")"

    if [[ -z "$CHECKSUM" || -z "$SIZE" ]]; then
        printf 'Manifest data is incomplete for platform %s.\n' "$PLATFORM" >&2
        exit 1
    fi

    FILE_NAME="$(binary_file_name "$RESOLVED_VERSION" "$PLATFORM")"
    DESTINATION_PATH="$BUNDLE_DIR/$FILE_NAME"
    DOWNLOAD_URL="$RELEASE_BASE_URL/$RESOLVED_VERSION/$PLATFORM/$(binary_leaf_name "$PLATFORM")"

    if [[ -f "$DESTINATION_PATH" ]]; then
        EXISTING_SIZE="$(wc -c <"$DESTINATION_PATH" | tr -d ' ')"
        EXISTING_HASH="$(hash_file "$DESTINATION_PATH")"
        if [[ "$EXISTING_SIZE" == "$SIZE" && "$EXISTING_HASH" == "$CHECKSUM" ]]; then
            printf 'Verified existing artifact: %s\n' "$FILE_NAME"
            SUCCESSFUL_PLATFORMS+=("$PLATFORM")
            continue
        fi
        rm -f "$DESTINATION_PATH"
    fi

    printf 'Downloading %s ...\n' "$PLATFORM"
    download_to_path "$DOWNLOAD_URL" "$DESTINATION_PATH"

    ACTUAL_SIZE="$(wc -c <"$DESTINATION_PATH" | tr -d ' ')"
    if [[ "$ACTUAL_SIZE" != "$SIZE" ]]; then
        rm -f "$DESTINATION_PATH"
        printf 'Downloaded size mismatch for %s.\n' "$FILE_NAME" >&2
        exit 1
    fi

    ACTUAL_HASH="$(hash_file "$DESTINATION_PATH")"
    if [[ "$ACTUAL_HASH" != "$CHECKSUM" ]]; then
        rm -f "$DESTINATION_PATH"
        printf 'Checksum mismatch for %s.\n' "$FILE_NAME" >&2
        exit 1
    fi

    SUCCESSFUL_PLATFORMS+=("$PLATFORM")
done

mapfile -t EXISTING_PLATFORMS < <(version_json_get_platforms "$VERSION_JSON_PATH")
FINAL_PLATFORMS=()
for PLATFORM in "${EXISTING_PLATFORMS[@]}" "${SUCCESSFUL_PLATFORMS[@]}"; do
    [[ -z "$PLATFORM" ]] && continue
    if [[ ! " ${FINAL_PLATFORMS[*]} " =~ [[:space:]]${PLATFORM}[[:space:]] ]]; then
        FINAL_PLATFORMS+=("$PLATFORM")
    fi
done

if [[ "${#FINAL_PLATFORMS[@]}" -eq 0 ]]; then
    printf 'No platform artifacts were staged successfully.\n' >&2
    exit 1
fi

write_version_json "$VERSION_JSON_PATH" "$RESOLVED_VERSION" "$MANIFEST_URL" "${FINAL_PLATFORMS[@]}"

printf 'Bundle directory: %s\n' "$BUNDLE_DIR"
printf 'Staged version: %s\n' "$RESOLVED_VERSION"
printf 'Platforms: %s\n' "$(IFS=,; printf '%s' "${FINAL_PLATFORMS[*]}")"
