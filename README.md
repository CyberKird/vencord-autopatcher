# Vencord Auto-Patcher

[![release](https://img.shields.io/github/v/release/CyberKird/vencord-autopatcher?label=release&color=22c55e)](https://github.com/CyberKird/vencord-autopatcher/releases/latest)
[![platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-blue)](https://github.com/CyberKird/vencord-autopatcher)
[![license](https://img.shields.io/badge/license-MIT-9ca3af)](LICENSE)

Every Discord update wipes Vencord; this re-patches it on login so you stop caring.

Runs on **Windows**, **Linux**, and **macOS**.

## How it works

1. Pulls the latest Vencord installer from the [official releases](https://github.com/Vencord/Installer)
2. Runs it against your local Discord install
3. Deletes the installer binary after patching
4. Starts Discord

## Quick start

### Windows

**One-click (recommended):**

1. Download [`setup.bat`](https://github.com/CyberKird/vencord-autopatcher/releases/latest/download/setup.bat)
2. Double-click it
3. Done. Restart to test, or say yes when asked to run now.

The script goes into `%LOCALAPPDATA%\VencordAutoPatcher\` and runs silently at every login.

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
| Help | *(Get-Help)* | `-h` | Show usage | (none) |

## Uninstall

- **Windows**: `Win+R` → `shell:startup` → delete the shortcut. Optionally delete `%LOCALAPPDATA%\VencordAutoPatcher\`.
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
