#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Vencord Auto-Patcher - UNIX edition (Linux / macOS)
#
# Updates itself from the latest GitHub release, downloads the latest Vencord
# installer for your platform, patches Discord, removes the installer, and
# optionally launches Discord.
#
# Usage:
#   ./vencord-autopatcher.sh [-b branch] [-n] [-u] [-V] [-h]
#
# Options:
#   -b  Vencord branch: stable (default), canary, or ptb
#   -n  Patch only; do not launch Discord afterward
#   -u  Skip the self-update check
#   -V  Print version and exit
#   -h  Show this help text
#
# Auto-start (Linux):
#   cp vencord-autopatcher.sh ~/.local/bin/
#   # Then add a .desktop file to ~/.config/autostart/ (see README)
#
# Dependencies: bash 4+, curl, chmod, and a working Discord install.
# The Vencord installer auto-detects your Discord path (apt, flatpak, snap, etc).
# ---------------------------------------------------------------------------
set -euo pipefail

readonly VERSION="1.3.0"
readonly REPO_URL="https://github.com/Vencord/Installer/releases/latest/download"
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/vencord-autopatcher"
readonly SCRIPT_NAME="${0##*/}"
readonly LOG_FILE="$CACHE_DIR/autopatcher.log"

readonly SELF_REPO="CyberKird/vencord-autopatcher"
readonly SELF_LATEST="https://github.com/$SELF_REPO/releases/latest"
readonly SELF_ASSET="$SELF_LATEST/download/vencord-autopatcher.sh"
# $0 has no directory when invoked from PATH; resolve it so self-update targets the real file
_self="$0"
[[ "$_self" == */* ]] || _self="$(command -v "$0" || echo "$0")"
readonly SELF_PATH="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || echo .)/$(basename "$_self")"
unset _self

# Valid branches accepted by the Vencord installer
readonly VALID_BRANCHES="stable canary ptb"

ORIG_ARGS=("$@")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

dim()  { printf '\033[2m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mx\033[0m %s\n' "$*" >&2; exit 1; }

step() {
    printf '\n\033[36m[%s]\033[0m \033[1m%s\033[0m\n' "$1" "$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE"
}

cleanup() {
    if [[ -n "${INSTALLER_EXEC:-}" ]]; then
        rm -rf "${INSTALLER_EXEC}" "${CACHE_DIR:?}/${INSTALLER_NAME}" \
            "${CACHE_DIR:?}/VencordInstaller.app" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Download with retries: at login the network is often not up yet.
fetch() {
    local url="$1" out="$2" attempts="${3:-3}" i
    for ((i = 1; i <= attempts; i++)); do
        if curl -fsSL --connect-timeout 10 -o "$out" "$url"; then
            return 0
        fi
        if ((i < attempts)); then
            warn "Download failed (attempt $i/$attempts), retrying in 10s..."
            sleep 10
        fi
    done
    return 1
}

# is_newer NEW CUR -> exit 0 when NEW is a strictly higher version than CUR.
# Pure bash: macOS ships a BSD sort without a dependable -V.
is_newer() {
    local -a a b
    local i x y
    IFS=. read -ra a <<< "${1#v}"
    IFS=. read -ra b <<< "${2#v}"
    for ((i = 0; i < 4; i++)); do
        x=$((10#${a[i]:-0}))
        y=$((10#${b[i]:-0}))
        if ((x > y)); then return 0; fi
        if ((x < y)); then return 1; fi
    done
    return 1
}

usage() {
    cat <<EOF
$(bold "Vencord Auto-Patcher - UNIX  v$VERSION")

Usage:  ./$SCRIPT_NAME [-b branch] [-n] [-u] [-V] [-h]

Options:
  -b  Vencord branch: stable (default), canary, or ptb
  -n  Do not launch Discord after patching
  -u  Skip the self-update check
  -V  Print version and exit
  -h  Show this help

$(dim "https://github.com/$SELF_REPO")
EOF
    exit 0
}

self_test() {
    is_newer 1.2.10 1.2.9 || die "FAIL: 1.2.10 > 1.2.9"
    is_newer v1.3.0 1.2.9 || die "FAIL: v-prefixed tag"
    is_newer 1.3 1.2.9    || die "FAIL: short version"
    ! is_newer 1.2.0 1.2.0  || die "FAIL: equal is not newer"
    ! is_newer 1.2.0 1.10.0 || die "FAIL: 1.2.0 < 1.10.0"
    ! is_newer 1.2.0 1.2.1  || die "FAIL: older is not newer"
    ok "All self-tests passed."
    exit 0
}

# Replaces this file with the newest release and re-execs. Never fatal:
# a failed self-update must not stop Discord from being patched.
self_update() {
    local tag remote staged

    if [[ ! -w "$SELF_PATH" ]]; then
        echo "Self-update: $SELF_PATH is not writable, skipping" >> "$LOG_FILE"
        return 0
    fi

    # The /releases/latest redirect gives us the tag without touching the rate-limited API
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' --connect-timeout 10 "$SELF_LATEST" 2>/dev/null)" || {
        echo "Self-update: could not reach GitHub, continuing on $VERSION" >> "$LOG_FILE"
        return 0
    }
    remote="${tag##*/}"

    if [[ ! "$remote" =~ ^v?[0-9]+(\.[0-9]+)+$ ]]; then
        echo "Self-update: unusable release tag '$remote', skipping" >> "$LOG_FILE"
        return 0
    fi
    if ! is_newer "$remote" "$VERSION"; then
        echo "Self-update: already on latest ($VERSION)" >> "$LOG_FILE"
        return 0
    fi

    staged="$CACHE_DIR/vencord-autopatcher.new"
    if ! fetch "$SELF_ASSET" "$staged" 2; then
        rm -f "$staged"
        warn "Could not download the update; continuing on $VERSION"
        return 0
    fi

    # Integrity gate: a truncated download or an HTML error page must never replace the script
    if ! bash -n "$staged" 2>/dev/null || ! grep -q '^readonly VERSION=' "$staged"; then
        rm -f "$staged"
        warn "Downloaded update failed validation; continuing on $VERSION"
        return 0
    fi

    chmod +x "$staged"
    mv -f "$staged" "$SELF_PATH"
    ok "Updated patcher $VERSION -> ${remote#v}, restarting..."
    # -u on the re-exec makes an update loop structurally impossible
    exec "$SELF_PATH" -u ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

BRANCH="stable"
NO_LAUNCH=0
NO_SELF_UPDATE=0

while getopts "b:nuVth" opt; do
    case "$opt" in
        b) BRANCH="$OPTARG" ;;
        n) NO_LAUNCH=1 ;;
        u) NO_SELF_UPDATE=1 ;;
        V) echo "Vencord Auto-Patcher $VERSION"; exit 0 ;;
        t) self_test ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

case " $VALID_BRANCHES " in
    *" $BRANCH "*) ;;
    *) die "Invalid branch '$BRANCH'. Valid options: $VALID_BRANCHES" ;;
esac

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

readonly OS="$(uname -s)"
case "$OS" in
    Linux)
        INSTALLER_NAME="VencordInstallerCli-linux"
        INSTALLER_URL="$REPO_URL/$INSTALLER_NAME"
        INSTALLER_EXEC="$CACHE_DIR/$INSTALLER_NAME"
        IS_ARCHIVE=0
        case "$BRANCH" in
            stable) DISCORD_CMD="discord" ;;
            canary) DISCORD_CMD="discord-canary" ;;
            ptb)    DISCORD_CMD="discord-ptb" ;;
        esac
        ;;
    Darwin)
        INSTALLER_NAME="VencordInstaller.MacOS.zip"
        INSTALLER_URL="$REPO_URL/$INSTALLER_NAME"
        INSTALLER_EXEC="$CACHE_DIR/VencordInstaller.app/Contents/MacOS/VencordInstaller"
        IS_ARCHIVE=1
        case "$BRANCH" in
            stable) DISCORD_APP="Discord" ;;
            canary) DISCORD_APP="Discord Canary" ;;
            ptb)    DISCORD_APP="Discord PTB" ;;
        esac
        DISCORD_CMD="/Applications/$DISCORD_APP.app/Contents/MacOS/$DISCORD_APP"
        ;;
    *)
        die "Unsupported OS: $OS (only Linux and macOS are supported)"
        ;;
esac

# ---------------------------------------------------------------------------
# Validate environment
# ---------------------------------------------------------------------------

command -v curl >/dev/null 2>&1 || die "curl is required but not found"

if [[ $NO_LAUNCH -eq 0 ]]; then
    command -v "$DISCORD_CMD" >/dev/null 2>&1 \
        || warn "Discord ($BRANCH) not found; patching will continue but launch may fail"
fi

mkdir -p "$CACHE_DIR"

echo "=== Vencord Auto-Patcher $VERSION $(date) ===" > "$LOG_FILE"
echo "OS: $OS, Branch: $BRANCH, NoLaunch: $NO_LAUNCH, NoSelfUpdate: $NO_SELF_UPDATE" >> "$LOG_FILE"

# ---------------------------------------------------------------------------
# Step 1 - Self-update
# ---------------------------------------------------------------------------

if [[ $NO_SELF_UPDATE -eq 1 ]]; then
    step "1/6" "Skipping self-update (-u flag set)"
else
    step "1/6" "Checking for a newer patcher..."
    self_update
fi

# ---------------------------------------------------------------------------
# Step 2 - Download
# ---------------------------------------------------------------------------

step "2/6" "Downloading latest Vencord installer for $OS..."
fetch "$INSTALLER_URL" "$CACHE_DIR/$INSTALLER_NAME" \
    || die "Could not download the Vencord installer"

# ---------------------------------------------------------------------------
# Step 3 - Prepare (extract on macOS, set executable on Linux)
# ---------------------------------------------------------------------------

if [[ $IS_ARCHIVE -eq 1 ]]; then
    step "3/6" "Extracting macOS bundle..."
    command -v unzip >/dev/null 2>&1 || die "unzip is required on macOS but not found"
    unzip -oq "$CACHE_DIR/$INSTALLER_NAME" -d "$CACHE_DIR"
    chmod +x "$INSTALLER_EXEC"
else
    step "3/6" "Preparing binary..."
    chmod +x "$INSTALLER_EXEC"
fi

# ---------------------------------------------------------------------------
# Step 4 - Patch
# ---------------------------------------------------------------------------

step "4/6" "Patching Discord (branch: $BRANCH)..."

set +e
"$INSTALLER_EXEC" -install -branch "$BRANCH" 2>&1 | tee -a "$LOG_FILE"
PATCH_EXIT=${PIPESTATUS[0]}
set -e

if [[ $PATCH_EXIT -ne 0 ]]; then
    die "Vencord installer exited with code $PATCH_EXIT"
fi

# ---------------------------------------------------------------------------
# Step 5 - Cleanup
# ---------------------------------------------------------------------------

step "5/6" "Removing installer..."
rm -rf "$CACHE_DIR/$INSTALLER_NAME" "$INSTALLER_EXEC" \
    "$CACHE_DIR/VencordInstaller.app" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 6 - Launch (optional)
# ---------------------------------------------------------------------------

if [[ $NO_LAUNCH -eq 1 ]]; then
    step "6/6" "Skipping launch (-n flag set)"
else
    step "6/6" "Launching Discord ($BRANCH)..."
    if command -v "$DISCORD_CMD" >/dev/null 2>&1; then
        nohup "$DISCORD_CMD" >/dev/null 2>&1 &
    else
        warn "Could not find Discord ($BRANCH). Install it or launch it manually."
    fi
fi

echo
ok "Done. Discord is patched with Vencord ($BRANCH)."
