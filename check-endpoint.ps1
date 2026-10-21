# This script is part of the open-source claude-cowork-endpoint-readiness toolkit.
# Read it, fork it, audit it. MIT licensed.

<#
.SYNOPSIS
  Read-only preflight for a Windows machine that will act as the Claude Cowork
  desktop bridge. No admin rights, no writes, no data leaves the machine.

.DESCRIPTION
  Prints one line per check (PASS / WARN / FAIL / INFO) and exits 1 when a
  documented requirement fails.

  Requirement sources (fetched 2026-10-21):
    support.claude.com/en/articles/13345190-get-started-with-claude-cowork
    support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork

.PARAMETER Json
  Emit a single JSON object instead of the table.

.PARAMETER NoNetwork
  Skip the HTTPS reachability checks.
#>
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$NoNetwork
)

$ErrorActionPreference = 'Continue'
$script:Failed = $false
$script:Rows = New-Object System.Collections.ArrayList

function Add-Row {
    param([string]$Status, [string]$Id, [string]$Detail)
    if ($Status -eq 'FAIL') { $script:Failed = $true }
    [void]$script:Rows.Add([pscustomobject]@{ id = $Id; status = $Status; detail = $Detail })
}

# 1. Platform.
$os = Get-CimInstance Win32_OperatingSystem
$osName = $os.Caption
$osVersion = "$($os.Version) (build $($os.BuildNumber))"
Add-Row 'PASS' 'platform' "$osName $osVersion"

# 2. Claude Desktop installed. Anthropic ships Cowork only in the latest Windows build.
$candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe'),
    'C:\Program Files\Claude\Claude.exe',
    'C:\Program Files (x86)\Claude\Claude.exe'
)
$appPath = $null
foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) { $appPath = $candidate; break }
}
$appVersion = 'unknown'
if ($appPath) {
    try { $appVersion = (Get-Item -LiteralPath $appPath).VersionInfo.ProductVersion } catch { }
    Add-Row 'PASS' 'app_installed' "Claude Desktop found at $appPath (version $appVersion). Update to the latest build before a rollout."
} else {
    Add-Row 'FAIL' 'app_installed' 'Claude Desktop not found in the standard install locations. Cowork has no browser-only path to local files, the browser or computer use.'
}

# 3. App running.
$proc = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
if ($proc) {
    Add-Row 'PASS' 'app_running' "Claude Desktop is running (PID $($proc[0].Id)). 'Connected' cannot be read locally - confirm the machine shows in Settings > Cowork."
} else {
    Add-Row 'WARN' 'app_running' 'Claude Desktop is not running. Start it before a task that needs a local file, the browser or computer use.'
}

# 4. Standby on AC power (a sleeping machine cannot answer Cowork).
$standby = $null
try {
    $raw = powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null
    $match = [regex]::Match(($raw -join "`n"), 'Current AC Power Setting Index:\s*(0x[0-9a-fA-F]+)')
    if ($match.Success) { $standby = $match.Groups[1].Value }
} catch { }
if ($standby -eq '0x00000000') {
    Add-Row 'PASS' 'sleep' 'Standby is disabled on AC power.'
} else {
    $standbyText = 'unknown'
    if ($standby) { $standbyText = $standby }
    Add-Row 'WARN' 'sleep' "Standby is enabled on AC power ($standbyText). A sleeping machine cannot answer Cowork; set a managed power profile for rollout machines."
}

# 5. Disk headroom. Not an Anthropic requirement: report only.
try {
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeGb = [math]::Round($drive.FreeSpace / 1GB, 1)
    Add-Row 'INFO' 'disk_free' "$freeGb GB free on C:. Not an Anthropic requirement, but Cowork writes deliverables to the machine through the app."
} catch {
    Add-Row 'INFO' 'disk_free' 'Free space on C: could not be read.'
}

# 6. Managed-device state (affects who can grant the app file and browser access).
$joined = $false
try {
    $dsreg = dsregcmd.exe /status 2>$null
    if (($dsreg -join "`n") -match 'AzureAdJoined\s*:\s*YES') { $joined = $true }
} catch { }
if ($joined) {
    Add-Row 'WARN' 'management' 'This machine is Entra-joined: file and browser access for the app may be granted only by policy. Get the profile approved before the pilot.'
} else {
    Add-Row 'PASS' 'management' 'No Entra join reported.'
}

# 7. Egress. Cowork respects the machine's egress permissions, and a TLS-inspecting proxy breaks the connection.
if (-not $NoNetwork) {
    foreach ($hostName in @('claude.ai', 'api.anthropic.com', 'claude.com')) {
        $ok = $false
        try { $ok = Test-NetConnection -ComputerName $hostName -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue } catch { }
        if ($ok) {
            Add-Row 'PASS' "egress_$hostName" "TCP 443 to $hostName works from this machine."
        } else {
            Add-Row 'FAIL' "egress_$hostName" "TCP 443 to $hostName failed. A machine behind an egress allowlist or a TLS-inspecting proxy will not stay connected."
        }
    }
} else {
    Add-Row 'INFO' 'egress' 'Network checks skipped (-NoNetwork).'
}

# 8. Proxy configuration. Report only, so a failed egress check has a cause.
$proxy = 'none'
try {
    $proxyRaw = (netsh.exe winhttp show proxy 2>$null) -join ' '
    if ($proxyRaw -match 'Proxy Server\(s\)\s*:\s*([^ ]+)') { $proxy = $Matches[1] }
    elseif ($env:HTTPS_PROXY) { $proxy = $env:HTTPS_PROXY }
} catch { }
Add-Row 'INFO' 'proxy' "WinHTTP proxy: $proxy"

# Report.
if ($Json) {
    $payload = [pscustomobject]@{
        platform    = $osName
        os_version  = $osVersion
        app_version = $appVersion
        failed      = $script:Failed
        checks      = $script:Rows
    }
    $payload | ConvertTo-Json -Depth 4
} else {
    Write-Output "Cowork endpoint readiness - $osName $osVersion"
    Write-Output '------------------------------------------------------------'
    foreach ($row in $script:Rows) {
        Write-Output ('{0,-4} {1,-14} {2}' -f $row.status, $row.id, $row.detail)
    }
    Write-Output '------------------------------------------------------------'
    if ($script:Failed) {
        Write-Output 'RESULT: not ready (a documented requirement failed).'
    } else {
        Write-Output 'RESULT: ready for a pilot, subject to the manual steps in checklist.md.'
    }
}

if ($script:Failed) { exit 1 } else { exit 0 }
