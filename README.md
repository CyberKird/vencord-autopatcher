# Vencord Auto-Patcher

[![release](https://img.shields.io/github/v/release/CyberKird/vencord-autopatcher?label=release&color=22c55e)](https://github.com/CyberKird/vencord-autopatcher/releases/latest)
[![platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-blue)](https://github.com/CyberKird/vencord-autopatcher)
[![license](https://img.shields.io/badge/license-MIT-9ca3af)](LICENSE)

Every Discord update wipes Vencord; this re-patches it on login so you stop caring.

Runs on **Windows**, **Linux**, and **macOS**.

## How it works

1. Updates itself if a newer patcher release exists, then restarts
2. Pulls the latest Vencord installer from the [official releases](https://github.com/Vencord/Installer)
3. Runs it against your local Discord install
4. Deletes the installer binary after patching
5. Starts Discord

On Windows it first checks whether Discord is still patched. Most logins Discord hasn't updated, so steps 2 to 4 are skipped and Discord opens right away. Pass `-Force` to patch anyway.

If patching fails (no network at login, GitHub down), Discord still opens, just without Vencord, and a Windows notification tells you so. The details are in the log.

## Quick start

### Windows

**One-click (recommended):**

1. Download [`setup.bat`](https://github.com/CyberKird/vencord-autopatcher/releases/latest/download/setup.bat)
2. Double-click it
3. Done. Restart to test, or say yes when asked to run now.

The script goes into `%LOCALAPPDATA%\VencordAutoPatcher\` and runs silently at every login.

**Discord's own "open on startup" gets switched off.** Otherwise Discord and the patcher start at the same time: Discord opens before it's patched, or opens twice. The patcher opens Discord itself once it's done. You can see this under Task Manager → Startup apps, and uninstalling switches it back on.

**Upgrading or removing:** run `setup.bat` again. If the patcher is already installed it asks whether to update or remove it. Updating replaces the existing install (including the old `C:\Scripts` location from early versions), clears duplicate startup entries and keeps your branch choice.

---

**Manual setup:**

1. Download `Vencord-AutoPatcher.ps1`
2. Move it somewhere permanent, e.g. `%LOCALAPPDATA%\VencordAutoPatcher\Vencord-AutoPatcher.ps1`
3. `Win+R` → `shell:startup`
4. Right-click → **New → Shortcut**
5. Paste this:
   ```
   powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\VencordAutoPatcher\Vencord-AutoPatcher.ps1"
   ```
6. Click Next, name it, Finish.

**Verify it works** by double-clicking the shortcut. Discord should open with Vencord active. It runs hidden, so no window appears.

Logs are at:
- **Windows**: `%TEMP%\VencordAutoPatcher.log`
- **Linux / macOS**: `~/.cache/vencord-autopatcher/autopatcher.log`

### Linux

```bash
# Run once to test
chmod +x vencord-autopatcher.sh
./vencord-autopatcher.sh

# Set up auto-start on login
cp vencord-autopatcher.sh ~/.local/bin/
cat > ~/.config/autostart/vencord-autopatcher.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Vencord Auto-Patcher
Exec=bash -c '~/.local/bin/vencord-autopatcher.sh'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
```

### macOS

```bash
# Run once to test
chmod +x vencord-autopatcher.sh
./vencord-autopatcher.sh

# Set up auto-start at login
# System Preferences → Users & Groups → Login Items → + → select vencord-autopatcher.sh
```

## Usage

```powershell
# Windows (PowerShell)
& "$env:LOCALAPPDATA\VencordAutoPatcher\Vencord-AutoPatcher.ps1"
& "$env:LOCALAPPDATA\VencordAutoPatcher\Vencord-AutoPatcher.ps1" -Branch canary
& "$env:LOCALAPPDATA\VencordAutoPatcher\Vencord-AutoPatcher.ps1" -NoLaunch
```

```bash
# UNIX (Linux / macOS)
./vencord-autopatcher.sh -b canary
./vencord-autopatcher.sh -n
```

| Flag | Windows | UNIX | Description | Default |
|------|---------|------|-------------|---------|
| Branch | `-Branch` | `-b` | `stable`, `canary`, or `ptb` | `stable` |
| Skip launch | `-NoLaunch` | `-n` | Patch only, don't start Discord | off |
| Skip self-update | `-NoSelfUpdate` | `-u` | Don't check for a newer patcher | off |
| Always patch | `-Force` | (always) | Patch even if Discord still looks patched | off |
| Install / upgrade | `-Install` | (manual, see above) | Copy to `%LOCALAPPDATA%` and add to startup | (none) |
| Uninstall | `-Uninstall` | (manual, see below) | Remove the patcher, restore Discord's startup entry | (none) |
| Version | `-Version` | `-V` | Print the patcher version | (none) |
| Help | `-Help` | `-h` | Show usage | (none) |

## Self-update

Self-update is **on by default**. On every run the patcher checks its own [latest release](https://github.com/CyberKird/vencord-autopatcher/releases/latest). If a newer version exists it replaces itself on disk and restarts with the same flags, so you set it up once and never download it again.

Before overwriting itself it syntax-checks the download, so a half-finished download or a GitHub error page can't leave you with a broken script. If GitHub is unreachable the check is skipped silently and Discord still gets patched.

**Prefer to update by hand?** Add `-NoSelfUpdate` (Windows) or `-u` (Linux / macOS) to the startup command. On Windows that means editing the shortcut in `shell:startup`; `setup.bat` keeps the flag when you upgrade later.

**Installed before v1.3.0?** Those versions can't update themselves. Run `setup.bat` once and you're on the self-updating version.

## Uninstall

- **Windows**: run `setup.bat` and pick **Remove**. That deletes the startup entry and the script, and switches Discord's own startup entry back on. Vencord stays installed; remove it with the [Vencord installer](https://github.com/Vencord/Installer) if you want it gone too.
- **Linux**: `rm ~/.config/autostart/vencord-autopatcher.desktop`
- **macOS**: System Preferences → Users & Groups → Login Items → select and remove

## Requirements

| Platform | Dependencies |
|----------|-------------|
| **Windows** | PowerShell 5.1+ (built-in) |
| **Linux** | bash 4+, `curl` |
| **macOS** | bash, `curl`, `unzip` (all built-in) |

Standard install location required. Flatpak, Snap, and similar are handled by the Vencord installer itself.

## Why?

Discord self-updates silently. Every update nukes Vencord. This runs on login, re-patches before Discord opens, and asks nothing of you after the initial setup.

## Credits

- [DrTankHead](https://www.reddit.com/user/DrTankHead) - UNIX port idea and `--src` flag concept
- [Vencord](https://github.com/Vendicated/Vencord) and [VencordInstaller](https://github.com/Vencord/Installer), the mod this wraps around

## License

MIT
