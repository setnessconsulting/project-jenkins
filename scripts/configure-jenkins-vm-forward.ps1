[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]:$')]
    [string] $ProtectedVolume = 'C:'
)

$ErrorActionPreference = 'Stop'
$vmName = 'SetnessJenkinsPilot'
$guestAddress = '192.168.218.2'
$guestPort = 18080
$listenAddress = '127.0.0.1'
$listenPort = 18080
$natName = 'SetnessJenkinsNat'
$networkPrefix = '192.168.218.0/24'
$hostStateDirectory = Join-Path $ProtectedVolume 'ProgramData\SetnessConsulting\JenkinsVM'
$serviceStatePath = Join-Path $hostStateDirectory 'iphlpsvc-startup-mode.txt'

& (Join-Path $PSScriptRoot 'hyperv-preflight.ps1') -ProtectedVolume $ProtectedVolume

$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if (-not $vm -or $vm.State -ne 'Running') {
    throw 'The dedicated Jenkins VM must be running before configuring the loopback forward.'
}
$nat = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
if (-not $nat -or $nat.InternalIPInterfaceAddressPrefix -ne $networkPrefix) {
    throw 'The expected isolated Jenkins VM NAT was not found; no port forward was configured.'
}
if (-not (Test-NetConnection -ComputerName $guestAddress -Port $guestPort -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    throw 'Jenkins is not reachable on the VM host-only address. Confirm the guest IP, firewall, and controller before configuring the forward.'
}

$existingMappings = @(netsh interface portproxy show v4tov4)
$matchingLine = $existingMappings | Where-Object { $_ -match '^\s*127\.0\.0\.1\s+18080\s+(\d{1,3}\.){3}\d{1,3}\s+18080\s*$' }
if ($matchingLine) {
    if ($matchingLine -match '^\s*127\.0\.0\.1\s+18080\s+192\.168\.218\.2\s+18080\s*$') {
        Write-Output 'The loopback-only Jenkins forward already points to the protected VM.'
        return
    }
    throw 'A different persistent portproxy already owns 127.0.0.1:18080. Inspect it manually; this script will not replace it.'
}

$listener = Get-NetTCPConnection -State Listen -LocalPort $listenPort -ErrorAction SilentlyContinue
if ($listener) {
    throw 'A local TCP listener already uses port 18080. Stop the old Docker Desktop Jenkins controller without removing its volume, then rerun this script.'
}

$ipHelper = Get-CimInstance -ClassName Win32_Service -Filter "Name='iphlpsvc'"
if (-not $ipHelper -or $ipHelper.StartMode -eq 'Disabled') {
    throw 'The Windows IP Helper service is disabled. Review the host policy before changing it.'
}
if ($ipHelper.StartMode -notin @('Auto', 'Manual')) {
    throw "The Windows IP Helper start mode '$($ipHelper.StartMode)' is not supported for reversible setup. No forward was configured."
}
if (Test-Path -LiteralPath $serviceStatePath) {
    throw 'A saved IP Helper startup-mode record already exists. Inspect it and the exact portproxy before proceeding.'
}

$null = New-Item -ItemType Directory -Path $hostStateDirectory -Force
Set-Content -LiteralPath $serviceStatePath -Value $ipHelper.StartMode -Encoding Ascii -NoNewline

try {
    if ($ipHelper.StartMode -eq 'Manual') {
        Set-Service -Name iphlpsvc -StartupType Automatic
    }
    if ((Get-Service -Name iphlpsvc).Status -ne 'Running') {
        Start-Service -Name iphlpsvc
    }

    & netsh.exe interface portproxy add v4tov4 `
        "listenaddress=$listenAddress" `
        "listenport=$listenPort" `
        "connectaddress=$guestAddress" `
        "connectport=$guestPort" `
        protocol=tcp | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Windows could not add the loopback-only port forward.'
    }

    $readback = @(netsh interface portproxy show v4tov4)
    if (-not ($readback | Where-Object { $_ -match '^\s*127\.0\.0\.1\s+18080\s+192\.168\.218\.2\s+18080\s*$' })) {
        throw 'Port-forward readback did not match the requested loopback-only target.'
    }
}
catch {
    $failedMapping = @(netsh interface portproxy show v4tov4) |
        Where-Object { $_ -match '^\s*127\.0\.0\.1\s+18080\s+192\.168\.218\.2\s+18080\s*$' }
    if ($failedMapping) {
        & netsh.exe interface portproxy delete v4tov4 "listenaddress=$listenAddress" "listenport=$listenPort" protocol=tcp | Out-Null
    }
    if ($ipHelper.StartMode -eq 'Manual' -and (Get-CimInstance -ClassName Win32_Service -Filter "Name='iphlpsvc'").StartMode -eq 'Auto') {
        Set-Service -Name iphlpsvc -StartupType Manual
    }
    Remove-Item -LiteralPath $serviceStatePath -Force -ErrorAction SilentlyContinue
    throw
}

Write-Output 'Jenkins is forwarded only from Windows 127.0.0.1:18080 to the Ubuntu VM host-only address. No LAN or internet listener was created.'
