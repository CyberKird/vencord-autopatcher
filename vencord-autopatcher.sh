#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Vencord Auto-Patcher - UNIX edition (Linux / macOS)
#
# Checks whether Discord is still patched. If not, updates itself from the
# latest GitHub release, downloads the latest Vencord installer for your
# platform, patches Discord and removes the installer. Then launches Discord.
#
# Usage:
#   ./vencord-autopatcher.sh [-b branch] [-n] [-u] [-f] [-V] [-h]
#
# Options:
#   -b  Vencord branch: stable (default), canary, or ptb
#   -n  Patch only; do not launch Discord afterward
#   -u  Skip the self-update check
#   -f  Patch even when Discord still looks patched
#   -V  Print version and exit
#   -h  Show this help text
#
# Auto-start (Linux):
#   cp vencord-autopatcher.sh ~/.local/bin/
#   # Then add a .desktop file to ~/.config/autostart/ (see README)
#
# Dependencies: bash 3.2+, curl, and a working Discord install.
# The Vencord installer auto-detects your Discord path (apt, flatpak, etc).
# ---------------------------------------------------------------------------
set -euo pipefail

readonly VERSION="1.6.1"
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
SELF_PATH="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || echo .)/$(basename "$_self")"
readonly SELF_PATH
unset _self

# Valid branches accepted by the Vencord installer
readonly VALID_BRANCHES="stable canary ptb"

ORIG_ARGS=("$@")

mkdir -p "$CACHE_DIR"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m>\033[0m %s\n' "$*"; log "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; log "WARN: $*"; }
die()  { printf '\033[31mx\033[0m %s\n' "$*" >&2; log "ERROR: $*"; exit 1; }

step() {
    printf '\n\033[36m[%s]\033[0m \033[1m%s\033[0m\n' "$1" "$2"
    log "[$1] $2"
}

# At login nobody watches the terminal, so a desktop notification is the only way a failure shows
notify() {
    if [[ "$(uname -s)" == Darwin ]]; then
        osascript -e "display notification \"$1\" with title \"Vencord Auto-Patcher\"" >/dev/null 2>&1 || true
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send "Vencord Auto-Patcher" "$1" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    [[ -n "${INSTALLER_EXEC:-}" ]] && rm -f "$INSTALLER_EXEC" 2>/dev/null
    rm -f "$CACHE_DIR/vencord-autopatcher.new" 2>/dev/null
    return 0
}
trap cleanup EXIT

# Download with retries: at login the network is often not up yet.
fetch() {
    local url="$1" out="$2" attempts="${3:-3}" i
    for ((i = 1; i <= attempts; i++)); do
        if curl -fsSL --connect-timeout 10 --max-time 300 -o "$out" "$url"; then
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

# Reads Discord resources folders on stdin. Exit 0 when at least one install exists and
# every one of them is still patched: Vencord moves the real app.asar to _app.asar and
# leaves a tiny loader in its place. A Discord update puts a full app.asar back, while a
# package manager leaves the old _app.asar lying around, so the loader size decides.
is_patched() {
    local res found=0
    while IFS= read -r res; do
        [[ -f "$res/app.asar" ]] || continue
        [[ -f "$res/_app.asar" ]] || return 1
        (($(wc -c < "$res/app.asar") < 65536)) || return 1
        found=1
    done
    ((found))
}

# Every resources folder the Vencord installer looks in for this branch
discord_resources() {
    local d n names newest
    if [[ "$OS" == Darwin ]]; then
        echo "/Applications/$DISCORD_APP.app/Contents/Resources"
        echo "$HOME/Applications/$DISCORD_APP.app/Contents/Resources"
        return 0
    fi
    case "$BRANCH" in
        stable) names="discord Discord" ;;
        canary) names="discord-canary DiscordCanary discordcanary" ;;
        ptb)    names="discord-ptb DiscordPTB discordptb" ;;
    esac
    for d in /usr/share /usr/lib64 /opt "$HOME/.local/share" "$HOME/.dvm"; do
        for n in $names; do echo "$d/$n/resources"; done
    done
    for d in /var/lib/flatpak/app "$HOME/.local/share/flatpak/app"; do
        echo "$d/$FLATPAK_ID/current/active/files/$DISCORD_CMD/resources"
    done
    # Builds that update themselves land in a fresh app-x.y.z folder; the newest one runs
    for d in "$HOME/.config/${DISCORD_CMD//-/}" "$HOME/.var/app/$FLATPAK_ID/config/discord"; do
        newest="$(printf '%s\n' "$d"/app-*/resources | sort -V | tail -n 1)"
        [[ -d "$newest" ]] && echo "$newest"
    done
    return 0
}

usage() {
    cat <<EOF
$(bold "Vencord Auto-Patcher - UNIX  v$VERSION")

Usage:  ./$SCRIPT_NAME [-b branch] [-n] [-u] [-f] [-V] [-h]

Options:
  -b  Vencord branch: stable (default), canary, or ptb
  -n  Do not launch Discord after patching
  -u  Skip the self-update check
  -f  Patch even when Discord still looks patched
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

    local tmp
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/patched" "$tmp/fresh" "$tmp/upgraded"
    echo loader > "$tmp/patched/app.asar"; echo real > "$tmp/patched/_app.asar"
    head -c 100000 /dev/zero > "$tmp/fresh/app.asar"
    head -c 100000 /dev/zero > "$tmp/upgraded/app.asar"; echo old > "$tmp/upgraded/_app.asar"
    is_patched <<< "$tmp/patched"              || die "FAIL: patched install is detected"
    ! is_patched <<< "$tmp/fresh"              || die "FAIL: fresh install needs patching"
    ! is_patched <<< "$tmp/upgraded"           || die "FAIL: package upgrade with stale _app.asar needs patching"
    ! is_patched <<< "$tmp/missing"            || die "FAIL: no Discord counts as unpatched"
    printf '%s\n' "$tmp/missing" "$tmp/patched" | is_patched || die "FAIL: missing folders are skipped"
    ! printf '%s\n' "$tmp/patched" "$tmp/fresh" | is_patched || die "FAIL: one unpatched install decides"
    rm -rf "$tmp"

    ok "All self-tests passed."
    exit 0
}

# Replaces this file with the newest release. Never fatal: a failed self-update
# must not stop Discord from being patched. With "restart" it re-execs the new
# version, otherwise the update applies on the next run.
self_update() {
    local mode="$1" tag remote staged

    if [[ ! -w "$SELF_PATH" ]]; then
        log "Self-update: $SELF_PATH is not writable, skipping"
        return 0
    fi

    # The /releases/latest redirect gives us the tag without touching the rate-limited API
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' --connect-timeout 10 --max-time 15 "$SELF_LATEST" 2>/dev/null)" || {
        log "Self-update: could not reach GitHub, continuing on $VERSION"
        return 0
    }
    remote="${tag##*/}"

    if [[ ! "$remote" =~ ^v?[0-9]+(\.[0-9]+)+$ ]]; then
        log "Self-update: unusable release tag '$remote', skipping"
        return 0
    fi
    if ! is_newer "$remote" "$VERSION"; then
        log "Self-update: already on latest ($VERSION)"
        return 0
    fi

    staged="$CACHE_DIR/vencord-autopatcher.new"
    if ! fetch "$SELF_ASSET" "$staged" 2; then
        warn "Could not download the update; continuing on $VERSION"
        return 0
    fi

    # Integrity gate: a truncated download or an HTML error page must never replace the script
    if ! bash -n "$staged" 2>/dev/null || ! grep -q '^readonly VERSION=' "$staged"; then
        warn "Downloaded update failed validation; continuing on $VERSION"
        return 0
    fi

    chmod +x "$staged"
    mv -f "$staged" "$SELF_PATH"
    ok "Updated patcher $VERSION -> ${remote#v}"
    if [[ "$mode" == restart ]]; then
        # -u on the re-exec makes an update loop structurally impossible
        exec "$SELF_PATH" -u ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
    fi
}

# A package upgrade puts a full app.asar back but leaves the old _app.asar behind. The
# installer takes that for a patched install, "unpatches" it and so restores the outdated
# Discord over the new one. Dropping the leftover first gives it a clean install to patch.
drop_stale_backups() {
    local res
    while IFS= read -r res; do
        [[ -f "$res/_app.asar" && -f "$res/app.asar" ]] || continue
        (($(wc -c < "$res/app.asar") >= 65536)) || continue
        if rm -f "$res/_app.asar"; then
            log "Removed $res/_app.asar left over from before a Discord upgrade"
        else
            warn "Could not remove the outdated $res/_app.asar"
        fi
    done
    return 0
}

patch_discord() {
    local rc

    drop_stale_backups < <(discord_resources)

    step "3/5" "Downloading latest Vencord installer for $OS..."
    fetch "$REPO_URL/$INSTALLER_NAME" "$INSTALLER_EXEC" || {
        warn "Could not download the Vencord installer"
        return 1
    }
    chmod +x "$INSTALLER_EXEC"

    step "4/5" "Patching Discord (branch: $BRANCH)..."
    set +e
    "$INSTALLER_EXEC" -install -branch "$BRANCH" 2>&1 | tee -a "$LOG_FILE"
    rc=${PIPESTATUS[0]}
    set -e
    rm -f "$INSTALLER_EXEC"

    if ((rc != 0)); then
        warn "Vencord installer exited with code $rc"
        return 1
    fi
}

launch_discord() {
    if [[ "$OS" == Darwin ]]; then
        # open -a finds the app in /Applications and ~/Applications alike
        open -a "$DISCORD_APP" 2>/dev/null && return 0
    elif command -v "$DISCORD_CMD" >/dev/null 2>&1; then
        nohup "$DISCORD_CMD" >/dev/null 2>&1 &
        return 0
    elif command -v flatpak >/dev/null 2>&1 && flatpak info "$FLATPAK_ID" >/dev/null 2>&1; then
        nohup flatpak run "$FLATPAK_ID" >/dev/null 2>&1 &
        return 0
    fi
    warn "Could not find Discord ($BRANCH). Install it or launch it manually."
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

BRANCH="stable"
NO_LAUNCH=0
NO_SELF_UPDATE=0
FORCE=0

while getopts "b:nufVth" opt; do
    case "$opt" in
        b) BRANCH="$OPTARG" ;;
        n) NO_LAUNCH=1 ;;
        u) NO_SELF_UPDATE=1 ;;
        f) FORCE=1 ;;
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

OS="$(uname -s)"
readonly OS
case "$OS" in
    Linux)
        INSTALLER_NAME="VencordInstallerCli-linux"
        case "$BRANCH" in
            stable) DISCORD_CMD="discord";        FLATPAK_ID="com.discordapp.Discord" ;;
            canary) DISCORD_CMD="discord-canary"; FLATPAK_ID="com.discordapp.DiscordCanary" ;;
            ptb)    DISCORD_CMD="discord-ptb";    FLATPAK_ID="com.discordapp.DiscordPTB" ;;
        esac
        ;;
    Darwin)
        INSTALLER_NAME="VencordInstallerCli-darwin"
        case "$BRANCH" in
            stable) DISCORD_APP="Discord" ;;
            canary) DISCORD_APP="Discord Canary" ;;
            ptb)    DISCORD_APP="Discord PTB" ;;
        esac
        ;;
    *)
        die "Unsupported OS: $OS (only Linux and macOS are supported)"
        ;;
esac
INSTALLER_EXEC="$CACHE_DIR/$INSTALLER_NAME"

command -v curl >/dev/null 2>&1 || die "curl is required but not found"

echo "=== Vencord Auto-Patcher $VERSION $(date) ===" > "$LOG_FILE"
log "OS: $OS, Branch: $BRANCH, NoLaunch: $NO_LAUNCH, NoSelfUpdate: $NO_SELF_UPDATE, Force: $FORCE"

# ---------------------------------------------------------------------------
# Steps 1-4 - Check, self-update, download, patch
# ---------------------------------------------------------------------------

PATCHED=0
FAILED=0

if [[ $FORCE -eq 0 ]] && is_patched < <(discord_resources); then
    # Most logins: Discord has not updated since the last patch, so nothing to download
    PATCHED=1
    step "1/5" "Discord ($BRANCH) is still patched, nothing to do (-f patches anyway)"
else
    step "1/5" "Discord ($BRANCH) needs patching"
    if [[ $NO_SELF_UPDATE -eq 1 ]]; then
        step "2/5" "Skipping self-update (-u flag set)"
    else
        # Before patching, so a fix in a newer patcher already applies to this run
        step "2/5" "Checking for a newer patcher..."
        self_update restart
    fi
    patch_discord || FAILED=1
fi

# ---------------------------------------------------------------------------
# Step 5 - Launch, even when patching failed: without Vencord beats not at all
# ---------------------------------------------------------------------------

if [[ $NO_LAUNCH -eq 1 ]]; then
    step "5/5" "Skipping launch (-n flag set)"
else
    step "5/5" "Launching Discord ($BRANCH)..."
    launch_discord
fi

# Discord is already open, so a slow network costs nothing here; the update applies next run
if [[ $PATCHED -eq 1 && $NO_SELF_UPDATE -eq 0 ]]; then
    self_update later
fi

if [[ $FAILED -eq 1 ]]; then
    notify "Discord was not patched. Details: $LOG_FILE"
    die "Discord was not patched. Details: $LOG_FILE"
fi

echo
ok "Done. Discord is patched with Vencord ($BRANCH)."
