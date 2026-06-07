# Vencord Auto-Patcher

Downloads the latest Vencord installer, patches Discord, and launches it — so you never deal with a broken client mod after an update again.

Works on **Windows**, **Linux**, and **macOS**.

## How it works

1. Fetches the **latest** Vencord installer binary from the [official releases](https://github.com/Vencord/Installer)
2. Runs it to patch your local Discord installation
3. Cleans up the downloaded binary (no leftovers)
4. Launches Discord

## Quick start

### Windows

Download `Vencord-AutoPatcher.ps1`, then choose a startup method:

**Startup folder (simplest)**

1. `Win+R` → `shell:startup`
2. Right-click → **New → Shortcut**
3. Location:
   ```
   powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\path\to\Vencord-AutoPatcher.ps1"
   ```

**Task Scheduler (more control)**

1. `Win+R` → `taskschd.msc`
2. **Create Task** → Trigger: *At log on*
3. Action: `powershell.exe` with arguments:
   ```
   -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\path\to\Vencord-AutoPatcher.ps1"
   ```

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
.\Vencord-AutoPatcher.ps1 -Branch canary
.\Vencord-AutoPatcher.ps1 -NoLaunch
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
| Help | *(Get-Help)* | `-h` | Show usage | — |

## Requirements

| Platform | Dependencies |
|----------|-------------|
| **Windows** | PowerShell 5.1+ (built-in) |
| **Linux** | bash 4+, `curl` |
| **macOS** | bash, `curl`, `unzip` (all built-in) |

Discord must be installed in its default location. The Vencord installer auto-detects alternative installs (Flatpak, Snap, etc.).

## Why?

Discord updates silently in the background. Each update wipes Vencord's patches. Instead of manually digging up the installer every time, this script handles it automatically — set it once and forget about it.

## Credits

- [DrTankHead](https://www.reddit.com/user/DrTankHead) — UNIX port idea and `--src` flag concept
- [Vencord](https://github.com/Vendicated/Vencord) & [VencordInstaller](https://github.com/Vencord/Installer) — the actual mod this wraps around

## License

MIT
