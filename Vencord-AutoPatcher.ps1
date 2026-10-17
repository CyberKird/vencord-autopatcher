<#
.SYNOPSIS
    Downloads the latest Vencord installer from GitHub, patches Discord, and launches Discord.
    Solves the problem of Vencord breaking every time Discord updates.

.DESCRIPTION
    This script:
    1. Checks whether Discord is still patched; if it is, skips straight to step 5
    2. Updates itself from the latest GitHub release (unless -NoSelfUpdate)
    3. Downloads the newest VencordInstallerCli.exe from the official GitHub release
    4. Runs it to patch your local Discord installation, then deletes it (no leftovers)
    5. Launches Discord, even when patching failed, and shows a notification if it did

    When Discord is still patched, the self-update check runs after Discord has opened,
    so a slow network at login never delays Discord.

    Use setup.bat (or -Install) to run it at every login.

    Logs are written to %TEMP%\VencordAutoPatcher.log

.PARAMETER Branch
    Vencord branch to install. Default: 'stable'. Other options: 'canary', 'ptb'.

.PARAMETER NoLaunch
    Skip launching Discord after patching.

.PARAMETER NoSelfUpdate
    Skip the self-update check.

.PARAMETER Force
    Patch even when Discord already looks patched.

.PARAMETER Install
    Copy this script to %LOCALAPPDATA%\VencordAutoPatcher and register it to run at login.
    Replaces any existing install, including the old C:\Scripts location, and keeps its flags.
    Also turns off Discord's own startup entry, since the patcher opens Discord itself.

.PARAMETER Uninstall
    Remove the startup entry and the installed script, and turn Discord's own startup entry
    back on if -Install turned it off. Vencord itself stays installed.

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

.EXAMPLE
    .\Vencord-AutoPatcher.ps1 -Install
    Installs the patcher to run at login, or upgrades an existing install in place.

.LINK
    https://github.com/Vencord/Installer
#>

param(
    [ValidateSet("stable", "canary", "ptb")]
    [string]$Branch = "stable",
    [switch]$NoLaunch,
    [switch]$NoSelfUpdate,
    [switch]$Force,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Version,
    [switch]$SelfTest,
    [switch]$Help
)

$ScriptVersion = "1.6.1"
$BranchGiven = $PSBoundParameters.ContainsKey("Branch")

if ($Version) { Write-Host "Vencord Auto-Patcher $ScriptVersion"; exit 0 }
if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
# Windows PowerShell 5.1 still defaults to TLS 1.0 on older builds; GitHub rejects it
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

$startupDir  = [Environment]::GetFolderPath("Startup")
$lnkName     = "Vencord-AutoPatcher.lnk"
$legacyPath  = "C:\Scripts\Vencord-AutoPatcher.ps1"
$runKey      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$approvedKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
# Discord startup entries that -Install turned off, so -Uninstall only restores those
$autostartMarker = Join-Path $installerDir "disabled-discord-autostart.txt"

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
    # At login the NIC is often not up yet - retry instead of failing the whole run
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            # Without a timeout a half-up network at login can stall a request for minutes
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
            return
        }
        catch {
            if ($i -eq $Attempts) { throw }
            Write-Log "Download failed (attempt $i/$Attempts): $($_.Exception.Message) - retrying in 10s"
            Start-Sleep -Seconds 10
        }
    }
}

function Invoke-SelfUpdate {
    # Returns $true when the script on disk was replaced by a newer release.
    $local = Get-NormalizedVersion $ScriptVersion
    $tag = (Invoke-RestMethod -Uri $selfApiUrl -UseBasicParsing -TimeoutSec 15 `
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
    Write-Host "Updated patcher $ScriptVersion -> $remote"
    Write-Log "Updated patcher $ScriptVersion -> $remote"
    return $true
}

function Get-FileScriptVersion {
    param([string]$Text)
    # Releases before 1.3.0 carried no version marker
    $m = [regex]::Match("$Text", '\$ScriptVersion\s*=\s*"([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return "pre-1.3"
}

function Get-LatestDiscordApp {
    param([string]$InstallDir)
    # Every Discord update lands in a fresh app-x.y.z folder; the newest one is what runs
    Get-ChildItem -Directory -Path $InstallDir -Filter "app-*" -ErrorAction SilentlyContinue |
        Sort-Object { Get-NormalizedVersion ($_.Name -replace '^app-', '') } |
        Select-Object -Last 1
}

function Test-DiscordPatched {
    param([string]$InstallDir)
    # Vencord moves the real app.asar to _app.asar and leaves a tiny loader in its place.
    # A fresh app-x.y.z folder from a Discord update starts out unpatched.
    $app = Get-LatestDiscordApp $InstallDir
    if (-not $app) { return $false }
    $resources = Join-Path $app.FullName "resources"
    $loader = Get-Item (Join-Path $resources "app.asar") -ErrorAction SilentlyContinue
    return [bool]((Test-Path (Join-Path $resources "_app.asar")) -and $loader -and $loader.Length -lt 64KB)
}

function Test-DiscordUnpacking {
    param([string]$InstallDir)
    # A Discord that is already open (taskbar, another startup entry) may be unpacking an
    # update into a new app-x.y.z folder right now, and app.asar is not there until it is done.
    # Patching then fails, after the Vencord installer has already killed Discord mid-update.
    # Only a recent folder counts, so a broken leftover never stalls every login.
    $app = Get-LatestDiscordApp $InstallDir
    return [bool]($app -and $app.CreationTime -gt (Get-Date).AddMinutes(-10) -and
        -not (Test-Path (Join-Path $app.FullName "resources\app.asar")))
}

function Get-ProcessStartArgs {
    param([string]$Command)
    # "Update.exe --processStart Discord.exe --process-start-args --start-minimized"
    $m = [regex]::Match("$Command", '--process-start-args\s+(?:"([^"]*)"|(\S+))')
    if ($m.Success) { return "$($m.Groups[1].Value)$($m.Groups[2].Value)" }
}

function Show-FailureNotice {
    param([string]$Text)
    # The script runs hidden at login, so a notification is the only way anyone sees a failure
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $tip = New-Object System.Windows.Forms.NotifyIcon
        $tip.Icon = [System.Drawing.SystemIcons]::Warning
        $tip.Text = "Vencord Auto-Patcher"
        $tip.Visible = $true
        $tip.ShowBalloonTip(10000, "Vencord Auto-Patcher", $Text, [System.Windows.Forms.ToolTipIcon]::Warning)
        Start-Sleep -Seconds 8
        $tip.Dispose()
    }
    catch { Write-Log "Could not show notification: $_" }
}

function Get-PatcherShortcuts {
    # Any startup shortcut that runs a copy of the patcher, whatever it is called
    $shell = New-Object -ComObject WScript.Shell
    foreach ($lnk in Get-ChildItem -Path $startupDir -Filter *.lnk -ErrorAction SilentlyContinue) {
        $lnkArgs = $shell.CreateShortcut($lnk.FullName).Arguments
        if ($lnkArgs -match 'Vencord-AutoPatcher\.ps1') {
            [pscustomobject]@{ Path = $lnk.FullName; Name = $lnk.Name; Arguments = $lnkArgs }
        }
    }
}

function Get-DiscordRunEntries {
    param([string]$DirName)
    $run = Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue
    if (-not $run) { return }
    # Match on the command, not the name, so "Discord" never catches DiscordPTB or DiscordCanary
    $pattern = '\\' + [regex]::Escape($DirName) + '\\Update\.exe'
    $run.PSObject.Properties | Where-Object { "$($_.Value)" -match $pattern } | ForEach-Object { $_.Name }
}

function Test-StartupDisabled {
    param([string]$Name)
    $bytes = (Get-ItemProperty -Path $approvedKey -Name $Name -ErrorAction SilentlyContinue).$Name
    return [bool]($bytes -and ($bytes[0] % 2) -eq 1)
}

function Set-StartupEnabled {
    param([string]$Name, [bool]$Enabled)
    # Same flag the Startup apps page writes: 2 = on, 3 = off, followed by a timestamp
    if (-not (Test-Path $approvedKey)) { New-Item -Path $approvedKey -Force | Out-Null }
    $flag = if ($Enabled) { 2 } else { 3 }
    $data = [byte[]](@($flag, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()))
    Set-ItemProperty -Path $approvedKey -Name $Name -Value $data -Type Binary
}

# powershell.exe -WindowStyle Hidden still flashes a console, or a whole Windows Terminal
# window where that is the default terminal. A headless conhost never shows one at all.
$conhost = Join-Path $env:SystemRoot "System32\conhost.exe"
$headless = [Environment]::OSVersion.Version.Build -ge 17763 -and (Test-Path $conhost)  # 1809+

function Set-StartupShortcut {
    param([string]$Path, [string]$PsArgs)
    $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
    if ($headless) {
        $sc.TargetPath = $conhost
        $sc.Arguments = "--headless powershell.exe $PsArgs"
    }
    else {
        $sc.TargetPath = "powershell.exe"
        $sc.Arguments = $PsArgs
        $sc.WindowStyle = 7  # starts minimized, so the moment before it hides stays off screen
    }
    $sc.Save()
}

function Install-Patcher {
    $target = Join-Path $installerDir "Vencord-AutoPatcher.ps1"

    $previous = @($target, $legacyPath) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($previous) {
        $prevVer = Get-FileScriptVersion (Get-Content -Raw $previous)
        if ($prevVer -eq $ScriptVersion) { Write-Host "Already on $ScriptVersion, refreshing the startup entry." }
        else { Write-Host "Found an existing install ($prevVer), replacing it with $ScriptVersion." }
    }

    # Two startup entries would patch Discord twice at login, so they all go,
    # but the flags they were started with carry over to the new one.
    $branch = $Branch
    $noLaunch = [bool]$NoLaunch
    $noSelf = [bool]$NoSelfUpdate
    $existing = @(Get-PatcherShortcuts)
    foreach ($lnk in $existing) {
        if (-not $BranchGiven -and $lnk.Arguments -match '-Branch\s+(stable|canary|ptb)') { $branch = $Matches[1] }
        if ($lnk.Arguments -match '-NoLaunch') { $noLaunch = $true }
        if ($lnk.Arguments -match '-NoSelfUpdate') { $noSelf = $true }
    }

    New-Item -ItemType Directory -Force -Path $installerDir | Out-Null
    if ($PSCommandPath -ne $target) { Copy-Item -Force $PSCommandPath $target }

    $runArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
    if ($branch -ne "stable") { $runArgs += " -Branch $branch" }
    if ($noLaunch) { $runArgs += " -NoLaunch" }
    if ($noSelf) { $runArgs += " -NoSelfUpdate" }

    Set-StartupShortcut (Join-Path $startupDir $lnkName) $runArgs

    # Old entries are removed only after the new one exists, so a failure never leaves nothing
    $existing | Where-Object { $_.Name -ne $lnkName } |
        ForEach-Object { Remove-Item -Force $_.Path -ErrorAction SilentlyContinue }
    if (Test-Path $legacyPath) {
        Remove-Item -Force $legacyPath -ErrorAction SilentlyContinue
        if (-not (Get-ChildItem -Force (Split-Path $legacyPath) -ErrorAction SilentlyContinue)) {
            Remove-Item (Split-Path $legacyPath) -ErrorAction SilentlyContinue
        }
    }

    # Discord's own startup entry races the patcher: Discord opens unpatched, or opens twice.
    # The patcher launches Discord itself, so switch Discord's entry off (unless -NoLaunch).
    if (-not $noLaunch) {
        $turnedOff = @(Get-Content $autostartMarker -ErrorAction SilentlyContinue)
        foreach ($name in Get-DiscordRunEntries $branchDirMap[$branch]) {
            if (Test-StartupDisabled $name) { continue }
            Set-StartupEnabled $name $false
            $turnedOff += $name
            Write-Host "Turned off Discord's own startup entry ('$name'); the patcher opens Discord after patching."
        }
        $turnedOff | Select-Object -Unique | Set-Content $autostartMarker
    }

    Write-Log "Installed $ScriptVersion to $target ($runArgs)"
    Write-Host "Installed $ScriptVersion (branch: $branch, self-update: $(if ($noSelf) { 'off' } else { 'on' }))."
}

function Uninstall-Patcher {
    $found = @(Get-PatcherShortcuts)
    $found | ForEach-Object { Remove-Item -Force $_.Path }

    foreach ($name in @(Get-Content $autostartMarker -ErrorAction SilentlyContinue)) {
        if ($name) {
            Set-StartupEnabled $name $true
            Write-Host "Turned Discord's own startup entry ('$name') back on."
        }
    }

    if (Test-Path $legacyPath) { Remove-Item -Force $legacyPath }
    # Runs fine from inside this folder: PowerShell has already read the whole script
    Remove-Item -Recurse -Force $installerDir -ErrorAction SilentlyContinue

    Write-Log "Uninstalled ($($found.Count) startup entries removed)"
    Write-Host "Vencord Auto-Patcher removed. Vencord itself is still installed; use the Vencord installer to remove it."
}

function Get-DiscordStartArgs {
    param([string]$DirName)
    # Discord keeps its launch flags (start minimized, user-added switches) on its own startup
    # entry. -Install turned that entry off, so carry the flags over instead of dropping them.
    $run = Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue
    foreach ($name in Get-DiscordRunEntries $DirName) {
        $startArgs = Get-ProcessStartArgs $run.$name
        if ($startArgs) { return $startArgs }
    }
}

if ($SelfTest) {
    function Assert { param([bool]$Cond, [string]$Msg) if (-not $Cond) { throw "FAIL: $Msg" }; Write-Host "ok  $Msg" }
    Assert ((Get-NormalizedVersion 'v1.2.10') -eq [version]'1.2.10') 'v-prefixed tag parses'
    Assert ((Get-NormalizedVersion 'v1.2.10') -gt (Get-NormalizedVersion '1.2.9')) '1.2.10 > 1.2.9'
    Assert ((Get-NormalizedVersion '1.3') -gt (Get-NormalizedVersion '1.2.9')) '1.3 > 1.2.9'
    Assert ((Get-NormalizedVersion '1.2.0') -le (Get-NormalizedVersion 'v1.2.0')) 'equal tag is not newer'
    Assert ($null -eq (Get-NormalizedVersion 'nightly')) 'non-numeric tag rejected'
    Assert ($null -eq (Get-NormalizedVersion '')) 'empty tag rejected'
    Assert ((Get-FileScriptVersion '$ScriptVersion = "1.3.0"') -eq '1.3.0') 'installed version is read from file'
    Assert ((Get-FileScriptVersion 'Write-Host hi') -eq 'pre-1.3') 'unversioned install is recognised'
    Assert ((Get-ProcessStartArgs '"C:\D\Update.exe" --processStart Discord.exe --process-start-args --start-minimized') -eq '--start-minimized') 'bare start flag is carried over'
    Assert ((Get-ProcessStartArgs '"C:\D\Update.exe" --processStart Discord.exe --process-start-args "--a --b"') -eq '--a --b') 'quoted start flags are carried over'
    Assert ($null -eq (Get-ProcessStartArgs '"C:\D\Update.exe" --processStart Discord.exe')) 'no start flags, nothing added'

    # Fake Discord installs: an older patched build next to a newer unpatched one
    $fake = Join-Path $env:TEMP "vap-selftest-$PID"
    function New-FakeBuild { param([string]$Name, [bool]$Patched)
        $res = New-Item -ItemType Directory -Force -Path "$fake\$Name\resources"
        if ($Patched) { Set-Content "$res\_app.asar" "real"; Set-Content "$res\app.asar" "loader" }
        else { [IO.File]::WriteAllBytes("$res\app.asar", (New-Object byte[] 100KB)) }
    }
    try {
        Assert (-not (Test-DiscordPatched $fake)) 'missing Discord install counts as unpatched'
        New-FakeBuild 'app-1.0.9' $true
        Assert (Test-DiscordPatched $fake) 'patched build is detected'
        New-FakeBuild 'app-1.0.10' $false
        Assert (-not (Test-DiscordPatched $fake)) 'newest build (1.0.10, not 1.0.9) decides'
        New-FakeBuild 'app-1.0.10' $true
        Assert (Test-DiscordPatched $fake) 'newest build patched again'
        Assert (-not (Test-DiscordUnpacking $fake)) 'finished build is not unpacking'
        $half = New-Item -ItemType Directory -Force -Path "$fake\app-1.0.11\resources"
        Assert (Test-DiscordUnpacking $fake) 'fresh build without app.asar is still unpacking'
        $half.Parent.CreationTime = (Get-Date).AddHours(-1)
        Assert (-not (Test-DiscordUnpacking $fake)) 'old broken build does not stall the run'

        Set-StartupShortcut "$fake\test.lnk" '-NoProfile -File "x\Vencord-AutoPatcher.ps1" -Branch ptb'
        $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut("$fake\test.lnk")
        Assert ($lnk.Arguments -match '-File "x\\Vencord-AutoPatcher\.ps1" -Branch ptb$') 'startup entry keeps the patcher flags'
        if ($headless) { Assert ($lnk.TargetPath -eq $conhost -and $lnk.Arguments -like '--headless powershell.exe *') 'startup entry runs in a headless console' }
        else { Assert ($lnk.WindowStyle -eq 7) 'startup entry starts minimized' }
    }
    finally { Remove-Item -Recurse -Force $fake -ErrorAction SilentlyContinue }

    Write-Host "`nAll self-tests passed."
    exit 0
}

if ($Install) { Install-Patcher; exit 0 }
if ($Uninstall) { Uninstall-Patcher; exit 0 }

# One run per login, so a single 1 MB rollover is plenty
if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 1MB) {
    Move-Item -Force $logFile "$logFile.old"
}

Write-Log "=== Vencord Auto-Patcher $ScriptVersion started ==="
Write-Log "Branch: $Branch, NoLaunch: $NoLaunch, NoSelfUpdate: $NoSelfUpdate, Force: $Force"

$dirName = $branchDirMap[$Branch]
$discordDir = "$env:LOCALAPPDATA\$dirName"
$failure = $null
$patched = $false

try {
    New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

    if (Test-DiscordUnpacking $discordDir) {
        Write-Log "Discord is unpacking an update, waiting for it to finish"
        $deadline = (Get-Date).AddMinutes(2)
        while ((Test-DiscordUnpacking $discordDir) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 3 }
    }

    $patched = -not $Force -and (Test-DiscordPatched $discordDir)
    if ($patched) {
        # Most logins: Discord has not updated since the last patch, so nothing to download
        Write-Step "1/5" "Discord ($Branch) is still patched, nothing to do (-Force patches anyway)"
    }
    else {
        Write-Step "1/5" "Discord ($Branch) needs patching"

        if ($NoSelfUpdate) {
            Write-Step "2/5" "Skipping self-update (-NoSelfUpdate set)"
        }
        else {
            # Before patching, so a fix in a newer patcher already applies to this run
            Write-Step "2/5" "Checking for a newer patcher..."
            $updated = $false
            try { $updated = Invoke-SelfUpdate }
            catch {
                # A failed self-update must never block patching Discord
                Write-Log "Self-update failed (continuing on $ScriptVersion): $($_.Exception.Message)"
                Remove-Item -Force "$PSCommandPath.new" -ErrorAction SilentlyContinue
            }
            if ($updated) {
                # -NoSelfUpdate on the re-exec makes an update loop structurally impossible
                $reArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
                            "-Branch", $Branch, "-NoSelfUpdate")
                if ($NoLaunch) { $reArgs += "-NoLaunch" }
                if ($Force) { $reArgs += "-Force" }
                & (Get-Process -Id $PID).Path @reArgs
                exit $LASTEXITCODE
            }
        }

        Write-Step "3/5" "Downloading latest Vencord installer..."
        Invoke-Download -Uri $installerUrl -OutFile $installerPath

        Write-Step "4/5" "Patching Discord ($Branch branch)..."
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $installerPath -install -branch $Branch 2>&1 | ForEach-Object {
            $line = "$_"
            Write-Host $line
            Write-Log $line
        }
        $patchExit = $LASTEXITCODE
        $ErrorActionPreference = $prev
        Remove-Item -Force $installerPath -ErrorAction SilentlyContinue
        if ($patchExit -ne 0) { throw "Installer exited with code $patchExit" }
    }
}
catch {
    # Exception.Message, not $_: on a 404, PowerShell 5.1 puts the whole HTML page in $_
    $failure = $_.Exception.Message
    Write-Log "ERROR: $failure"
    Write-Host "ERROR: $failure" -ForegroundColor Red
    Remove-Item -Force $installerPath -ErrorAction SilentlyContinue
}

# Discord opens even when patching failed (offline at login, GitHub down): without Vencord
# beats not at all, especially with Discord's own startup entry switched off.
if ($NoLaunch) {
    Write-Step "5/5" "Skipping Discord launch (-NoLaunch set)"
}
else {
    Write-Step "5/5" "Launching Discord ($Branch)..."
    $updater = "$discordDir\Update.exe"
    if (Test-Path $updater) {
        $launchArgs = @("--processStart", "$dirName.exe")
        $startArgs = Get-DiscordStartArgs $dirName
        if ($startArgs) {
            $launchArgs += "--process-start-args", "`"$startArgs`""
            Write-Log "Discord start flags: $startArgs"
        }
        Start-Process -FilePath $updater -ArgumentList $launchArgs
    }
    else {
        Write-Warning "$dirName Update.exe not found. Is that Discord branch installed?"
        Write-Log "WARN: $updater not found"
    }
}

# Startup entries from before 1.6.1 run powershell.exe directly and flash a window at login.
# Self-update never reruns -Install, so move them to the headless console here.
try {
    $lnkPath = Join-Path $startupDir $lnkName
    if ($headless -and (Test-Path $lnkPath)) {
        $old = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
        if ($old.TargetPath -match 'powershell\.exe$' -and $old.Arguments -match 'Vencord-AutoPatcher\.ps1') {
            Set-StartupShortcut $lnkPath $old.Arguments
            Write-Log "Startup entry now runs in a headless console (no window at login)"
        }
    }
}
catch { Write-Log "Could not update the startup entry: $($_.Exception.Message)" }

if ($patched -and -not $NoSelfUpdate) {
    # Discord is already open, so a slow network costs nothing here; the update applies next login
    try { Invoke-SelfUpdate | Out-Null }
    catch {
        Write-Log "Self-update failed (staying on $ScriptVersion): $($_.Exception.Message)"
        Remove-Item -Force "$PSCommandPath.new" -ErrorAction SilentlyContinue
    }
}

if ($failure) {
    $opened = if ($NoLaunch) { "Discord was not patched" } else { "Discord opened without Vencord" }
    Show-FailureNotice "$opened. Details: %TEMP%\VencordAutoPatcher.log"
    exit 1
}

Write-Log "=== Done ==="
