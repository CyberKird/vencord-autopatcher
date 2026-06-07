<#
.SYNOPSIS
    Downloads the latest Vencord installer from GitHub, patches Discord, and launches Discord.
    Solves the problem of Vencord breaking every time Discord updates.

.DESCRIPTION
    This script:
    1. Downloads the newest VencordInstallerCli.exe straight from the official GitHub release
    2. Runs it to patch your local Discord installation
    3. Cleans up the downloaded installer (no leftovers)
    4. Launches Discord

    Set it to run at Windows startup via Task Scheduler or Startup folder.

.PARAMETER Branch
    Vencord branch to install. Default: 'stable'. Other options: 'canary', 'ptb'.

.PARAMETER NoLaunch
    Skip launching Discord after patching.

.EXAMPLE
    .\Vencord-AutoPatcher.ps1
    Downloads latest Vencord, patches Discord (stable branch), launches Discord.

.EXAMPLE
    .\Vencord-AutoPatcher.ps1 -Branch canary -NoLaunch
    Patches Discord Canary and does not launch.

.LINK
    https://github.com/Vencord/Installer
#>

param(
    [string]$Branch = "stable",
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

$installerDir = "$env:LOCALAPPDATA\VencordAutoPatcher"
$installerPath = "$installerDir\VencordInstallerCli.exe"
$discordUpdateExe = "$env:LOCALAPPDATA\Discord\Update.exe"
$installerUrl = "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe"

New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

try {
    Write-Host "[1/4] Downloading latest Vencord installer..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

    Write-Host "[2/4] Patching Discord ($Branch branch)..."
    & $installerPath -install -branch $Branch

    Write-Host "[3/4] Cleaning up..."
    Remove-Item -Force $installerPath -ErrorAction SilentlyContinue

    if (-not $NoLaunch) {
        Write-Host "[4/4] Launching Discord..."
        if (Test-Path $discordUpdateExe) {
            Start-Process -FilePath $discordUpdateExe -ArgumentList "--processStart", "Discord.exe"
        }
        else {
            Write-Warning "Discord not found at $discordUpdateExe"
        }
    }
    else {
        Write-Host "[4/4] Skipping Discord launch (-NoLaunch was set)"
    }

    Write-Host "Done."
}
catch {
    Remove-Item -Force $installerPath -ErrorAction SilentlyContinue
    throw
}
