[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]:$')]
    [string] $ProtectedVolume = 'C:'
)

$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Removing the Windows port forward requires an elevated Administrator PowerShell. No host changes were made.'
}

$listenAddress = '127.0.0.1'
$listenPort = 18080
$forwardPattern = '^\s*127\.0\.0\.1\s+18080\s+192\.168\.218\.2\s+18080\s*$'
$listenPattern = '^\s*127\.0\.0\.1\s+18080\s+'
$hostStateDirectory = Join-Path $ProtectedVolume 'ProgramData\SetnessConsulting\JenkinsVM'
$serviceStatePath = Join-Path $hostStateDirectory 'iphlpsvc-startup-mode.txt'

$existingMappings = @(netsh interface portproxy show v4tov4)
$conflictingMapping = $existingMappings | Where-Object { $_ -match $listenPattern -and $_ -notmatch $forwardPattern }
if ($conflictingMapping) {
    throw '127.0.0.1:18080 now points somewhere else. No mapping or service setting was changed.'
}

$matchingMapping = $existingMappings | Where-Object { $_ -match $forwardPattern }
if ($matchingMapping) {
    & netsh.exe interface portproxy delete v4tov4 "listenaddress=$listenAddress" "listenport=$listenPort" protocol=tcp | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Windows could not remove the exact loopback-to-VM port forward.'
    }
}

$readback = @(netsh interface portproxy show v4tov4)
if ($readback | Where-Object { $_ -match $forwardPattern }) {
    throw 'The exact port forward is still present after removal; IP Helper settings were left unchanged.'
}

$mappingPattern = '^\s*(?:\d{1,3}\.){3}\d{1,3}\s+\d+\s+(?:\d{1,3}\.){3}\d{1,3}\s+\d+\s*$'
$remainingMappings = @($readback | Where-Object { $_ -match $mappingPattern })
if ($remainingMappings.Count -gt 0) {
    Write-Output 'The Jenkins forward is removed. Other portproxy mappings remain, so IP Helper startup settings were preserved.'
    return
}

if (-not (Test-Path -LiteralPath $serviceStatePath -PathType Leaf)) {
    Write-Output 'The Jenkins forward is removed. No saved IP Helper startup-mode change was found.'
    return
}

$originalStartMode = (Get-Content -LiteralPath $serviceStatePath -Raw).Trim()
if ($originalStartMode -notin @('Auto', 'Manual')) {
    throw 'The saved IP Helper startup mode is unexpected; the forward is removed, but the service setting was not changed.'
}
$currentIpHelper = Get-CimInstance -ClassName Win32_Service -Filter "Name='iphlpsvc'"
if ($currentIpHelper.StartMode -eq 'Auto' -and $originalStartMode -eq 'Manual') {
    Set-Service -Name iphlpsvc -StartupType Manual
}
elseif ($currentIpHelper.StartMode -ne $originalStartMode) {
    Write-Output 'The forward is removed. IP Helper was changed independently after setup, so its current startup mode was preserved.'
}
Remove-Item -LiteralPath $serviceStatePath -Force
Write-Output 'The exact Jenkins forward is removed. The recorded IP Helper startup mode was restored where it remained unchanged.'
