<#
.SYNOPSIS
    Downloads the latest Vencord installer from GitHub, patches Discord, and launches Discord.
    Solves the problem of Vencord breaking every time Discord updates.

.DESCRIPTION
    This script:
    1. Updates itself from the latest GitHub release (unless -NoSelfUpdate)
    2. Downloads the newest VencordInstallerCli.exe straight from the official GitHub release
    3. Runs it to patch your local Discord installation
    4. Cleans up the downloaded installer (no leftovers)
    5. Launches Discord

    Set it to run at Windows startup via Task Scheduler or Startup folder.
    Use setup.bat for automatic one-click setup.

    Logs are written to %TEMP%\VencordAutoPatcher.log

.PARAMETER Branch
    Vencord branch to install. Default: 'stable'. Other options: 'canary', 'ptb'.

.PARAMETER NoLaunch
    Skip launching Discord after patching.

.PARAMETER NoSelfUpdate
    Skip the self-update check.

.PARAMETER Version
    Print the script version and exit.

.PARAMETER SelfTest
    Run the built-in assertions and exit.

.PARAMETER Help
    Show this help text.

.EXAMPLE
    .\Vencord-AutoPatcher.ps1
    Updates itself, downloads latest Vencord, patches Discord (stable branch), launches Discord.

.EXAMPLE
    .\Vencord-AutoPatcher.ps1 -Branch canary -NoLaunch
    Patches Discord Canary and does not launch.

.LINK
    https://github.com/Vencord/Installer
#>

param(
    [ValidateSet("stable", "canary", "ptb")]
    [string]$Branch = "stable",
    [switch]$NoLaunch,
    [switch]$NoSelfUpdate,
    [switch]$Version,
    [switch]$SelfTest,
    [switch]$Help
)

$ScriptVersion = "1.3.0"

if ($Version) { Write-Host "Vencord Auto-Patcher $ScriptVersion"; exit 0 }
if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
# ponytail: Windows PowerShell 5.1 still defaults to TLS 1.0 on older builds; GitHub rejects it
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$logFile      = Join-Path $env:TEMP "VencordAutoPatcher.log"
$installerDir = "$env:LOCALAPPDATA\VencordAutoPatcher"
$installerPath = "$installerDir\VencordInstallerCli.exe"
$installerUrl = "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe"

$selfRepo   = "CyberKird/vencord-autopatcher"
$selfApiUrl = "https://api.github.com/repos/$selfRepo/releases/latest"
$selfAssetUrl = "https://github.com/$selfRepo/releases/latest/download/Vencord-AutoPatcher.ps1"

# branch -> install folder under %LOCALAPPDATA%
$branchDirMap = @{
    "stable" = "Discord"
    "ptb"    = "DiscordPTB"
    "canary" = "DiscordCanary"
}

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$stamp  $Message" | Out-File -Append -Encoding utf8 $logFile
}

function Write-Step {
    param([string]$Num, [string]$Label)
    $msg = "[$Num] $Label"
    Write-Host $msg
    Write-Log $msg
}

function Get-NormalizedVersion {
    param([string]$Tag)
    # Accepts "v1.2.3" or "1.2.3"; returns $null for anything without a dotted number
    $m = [regex]::Match("$Tag", '^v?(\d+(?:\.\d+)+)$')
    if (-not $m.Success) { return $null }
    return [version]$m.Groups[1].Value
}

function Invoke-Download {
    param([string]$Uri, [string]$OutFile, [int]$Attempts = 3)
    # ponytail: at login the NIC is often not up yet - retry instead of failing the whole run
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
            return
        }
        catch {
            if ($i -eq $Attempts) { throw }
            Write-Log "Download failed (attempt $i/$Attempts): $_ - retrying in 10s"
            Start-Sleep -Seconds 10
        }
    }
}

function Invoke-SelfUpdate {
    # Returns $true when the script on disk was replaced by a newer release.
    $local = Get-NormalizedVersion $ScriptVersion
    $tag = (Invoke-RestMethod -Uri $selfApiUrl -UseBasicParsing `
            -Headers @{ "User-Agent" = "vencord-autopatcher" }).tag_name
    $remote = Get-NormalizedVersion $tag

    if (-not $remote) { Write-Log "Self-update: unusable release tag '$tag', skipping"; return $false }
    if ($remote -le $local) { Write-Log "Self-update: already on latest ($ScriptVersion)"; return $false }

    $staged = "$PSCommandPath.new"
    Invoke-Download -Uri $selfAssetUrl -OutFile $staged -Attempts 2

    # Integrity gate: a truncated download or an HTML error page must never replace the script
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($staged, [ref]$null, [ref]$errors) | Out-Null
    $body = Get-Content -Raw $staged
    if ($errors.Count -gt 0 -or $body -notmatch '\$ScriptVersion\s*=') {
        Remove-Item -Force $staged -ErrorAction SilentlyContinue
        Write-Log "Self-update: downloaded file failed validation, keeping $ScriptVersion"
        return $false
    }

    Move-Item -Force $staged $PSCommandPath
    Write-Step "1/5" "Updated patcher $ScriptVersion -> $remote, restarting..."
    return $true
}

if ($SelfTest) {
    function Assert { param([bool]$Cond, [string]$Msg) if (-not $Cond) { throw "FAIL: $Msg" }; Write-Host "ok  $Msg" }
    Assert ((Get-NormalizedVersion 'v1.2.10') -eq [version]'1.2.10') 'v-prefixed tag parses'
    Assert ((Get-NormalizedVersion 'v1.2.10') -gt (Get-NormalizedVersion '1.2.9')) '1.2.10 > 1.2.9'
    Assert ((Get-NormalizedVersion '1.3') -gt (Get-NormalizedVersion '1.2.9')) '1.3 > 1.2.9'
    Assert ((Get-NormalizedVersion '1.2.0') -le (Get-NormalizedVersion 'v1.2.0')) 'equal tag is not newer'
    Assert ($null -eq (Get-NormalizedVersion 'nightly')) 'non-numeric tag rejected'
    Assert ($null -eq (Get-NormalizedVersion '')) 'empty tag rejected'
    Write-Host "`nAll self-tests passed."
    exit 0
}

# ponytail: single 1 MB rotation, this appends once per login - real rotation is overkill
if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 1MB) {
    Move-Item -Force $logFile "$logFile.old"
}

Write-Log "=== Vencord Auto-Patcher $ScriptVersion started ==="
Write-Log "Branch: $Branch, NoLaunch: $NoLaunch, NoSelfUpdate: $NoSelfUpdate"

try {
    New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

    if ($NoSelfUpdate) {
        Write-Step "1/5" "Skipping self-update (-NoSelfUpdate set)"
    }
    else {
        Write-Step "1/5" "Checking for a newer patcher..."
        $updated = $false
        try { $updated = Invoke-SelfUpdate }
        catch {
            # A failed self-update must never block patching Discord
            Write-Log "Self-update failed (continuing on $ScriptVersion): $_"
            Remove-Item -Force "$PSCommandPath.new" -ErrorAction SilentlyContinue
        }
        if ($updated) {
            # -NoSelfUpdate on the re-exec makes an update loop structurally impossible
            $reArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
                        "-Branch", $Branch, "-NoSelfUpdate")
            if ($NoLaunch) { $reArgs += "-NoLaunch" }
            & (Get-Process -Id $PID).Path @reArgs
            exit $LASTEXITCODE
        }
    }

    Write-Step "2/5" "Downloading latest Vencord installer..."
    Invoke-Download -Uri $installerUrl -OutFile $installerPath

    Write-Step "3/5" "Patching Discord ($Branch branch)..."
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $installerPath -install -branch $Branch 2>&1 | ForEach-Object {
        $line = "$_"
        Write-Host $line
        Write-Log $line
    }
    $patchExit = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($patchExit -ne 0) { throw "Installer exited with code $patchExit" }

    Write-Step "4/5" "Cleaning up..."
    Remove-Item -Force $installerPath -ErrorAction SilentlyContinue

    if ($NoLaunch) {
        Write-Step "5/5" "Skipping Discord launch (-NoLaunch set)"
    }
    else {
        Write-Step "5/5" "Launching Discord ($Branch)..."
        $dirName = $branchDirMap[$Branch]
        $updater = "$env:LOCALAPPDATA\$dirName\Update.exe"
        if (Test-Path $updater) {
            Start-Process -FilePath $updater -ArgumentList "--processStart", "$dirName.exe"
        }
        else {
            Write-Warning "$dirName Update.exe not found. Is that Discord branch installed?"
            Write-Log "WARN: $updater not found"
        }
    }

    Write-Log "=== Done ==="
}
catch {
    Write-Log "ERROR: $_"
    Remove-Item -Force $installerPath -ErrorAction SilentlyContinue
    throw
}
