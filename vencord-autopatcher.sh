#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Vencord Auto-Patcher - UNIX edition (Linux / macOS)
#
# Downloads the latest Vencord installer for your platform, patches Discord,
# removes the installer, and optionally launches Discord.
#
# Usage:
#   ./vencord-autopatcher.sh [-b branch] [-n] [-h]
#
# Options:
#   -b  Vencord branch: stable (default), canary, or ptb
#   -n  Patch only; do not launch Discord afterward
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

readonly REPO_URL="https://github.com/Vencord/Installer/releases/latest/download"
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/vencord-autopatcher"
readonly SCRIPT_NAME="${0##*/}"
readonly LOG_FILE="$CACHE_DIR/autopatcher.log"

# Valid branches accepted by the Vencord installer
readonly VALID_BRANCHES="stable canary ptb"

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

usage() {
    cat <<EOF
$(bold "Vencord Auto-Patcher - UNIX")

Usage:  ./$SCRIPT_NAME [-b branch] [-n] [-h]

Options:
  -b  Vencord branch: stable (default), canary, or ptb
  -n  Do not launch Discord after patching
  -h  Show this help

$(dim "https://github.com/CyberKird/vencord-autopatcher")
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

BRANCH="stable"
NO_LAUNCH=0

while getopts "b:nh" opt; do
    case "$opt" in
        b) BRANCH="$OPTARG" ;;
        n) NO_LAUNCH=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

if [[ ! " $VALID_BRANCHES " =~ " $BRANCH " ]]; then
    die "Invalid branch '$BRANCH'. Valid options: $VALID_BRANCHES"
fi

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

echo "=== Vencord Auto-Patcher $(date) ===" > "$LOG_FILE"
echo "OS: $OS, Branch: $BRANCH, NoLaunch: $NO_LAUNCH" >> "$LOG_FILE"

# ---------------------------------------------------------------------------
# Step 1 - Download
# ---------------------------------------------------------------------------

step "1/5" "Downloading latest Vencord installer for $OS..."
curl -fsSL --progress-bar -o "$CACHE_DIR/$INSTALLER_NAME" "$INSTALLER_URL"

# ---------------------------------------------------------------------------
# Step 2 - Prepare (extract on macOS, set executable on Linux)
# ---------------------------------------------------------------------------

if [[ $IS_ARCHIVE -eq 1 ]]; then
    step "2/5" "Extracting macOS bundle..."
    command -v unzip >/dev/null 2>&1 || die "unzip is required on macOS but not found"
    unzip -oq "$CACHE_DIR/$INSTALLER_NAME" -d "$CACHE_DIR"
    chmod +x "$INSTALLER_EXEC"
else
    step "2/5" "Preparing binary..."
    chmod +x "$INSTALLER_EXEC"
fi

# ---------------------------------------------------------------------------
# Step 3 - Patch
# ---------------------------------------------------------------------------

step "3/5" "Patching Discord (branch: $BRANCH)..."

set +e
"$INSTALLER_EXEC" -install -branch "$BRANCH" 2>&1 | tee -a "$LOG_FILE"
PATCH_EXIT=${PIPESTATUS[0]}
set -e

if [[ $PATCH_EXIT -ne 0 ]]; then
    die "Vencord installer exited with code $PATCH_EXIT"
fi

# ---------------------------------------------------------------------------
# Step 4 - Cleanup
# ---------------------------------------------------------------------------

step "4/5" "Removing installer..."
rm -rf "$CACHE_DIR/$INSTALLER_NAME" "$INSTALLER_EXEC" \
    "$CACHE_DIR/VencordInstaller.app" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 5 - Launch (optional)
# ---------------------------------------------------------------------------

if [[ $NO_LAUNCH -eq 1 ]]; then
    step "5/5" "Skipping launch (-n flag set)"
else
    step "5/5" "Launching Discord ($BRANCH)..."
    if command -v "$DISCORD_CMD" >/dev/null 2>&1; then
        nohup "$DISCORD_CMD" >/dev/null 2>&1 &
    else
        warn "Could not find Discord ($BRANCH). Install it or launch it manually."
    fi
fi

echo
ok "Done. Discord is patched with Vencord ($BRANCH)."
