# Vencord Auto-Patcher

Automatically re-patches Discord with Vencord every time your PC starts — so Discord updates never break your client mod again.

## How it works

1. Downloads the **latest** `VencordInstallerCli.exe` directly from the [official Vencord GitHub](https://github.com/Vencord/Installer)
2. Runs the installer to patch your local Discord
3. Cleans up the downloaded installer (no leftover files)
4. Launches Discord

## One-time setup

### Option A: Startup folder (simplest)

1. Download `Vencord-AutoPatcher.ps1`
2. Press `Win+R`, type `shell:startup`, hit Enter
3. Right-click → **New → Shortcut**
4. Location:  
   ```
   powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\PATH\TO\Vencord-AutoPatcher.ps1"
   ```
5. Name it whatever you want. Done.

### Option B: Task Scheduler (more control)

1. Press `Win+R`, type `taskschd.msc`
2. **Create Task** → tab **General**: name it `Vencord AutoPatcher`
3. Tab **Triggers** → New → **At log on**
4. Tab **Actions** → New → Program: `powershell.exe`, Arguments:
   ```
   -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\PATH\TO\Vencord-AutoPatcher.ps1"
   ```
5. Tab **Conditions** → uncheck *Start only if on AC power*
6. OK. Done.

## Usage (manual run)

```powershell
.\Vencord-AutoPatcher.ps1
```

### Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Branch` | Vencord branch (`stable`, `canary`, `ptb`) | `stable` |
| `-NoLaunch` | Patch Discord but don't launch it | (off) |

```powershell
.\Vencord-AutoPatcher.ps1 -Branch canary
.\Vencord-AutoPatcher.ps1 -NoLaunch
```

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built into Windows)
- Discord installed in the default location (`%LOCALAPPDATA%\Discord`)

## Why?

Discord updates silently in the background. When it does, Vencord's patches get wiped and you have to manually re-run the installer. This script automates that — just set it once and forget about it.

## License

MIT — do whatever you want.
