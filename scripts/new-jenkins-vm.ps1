[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $UbuntuServerIsoPath,
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string] $UbuntuIsoSha256,
    [ValidatePattern('^[A-Za-z]:$')]
    [string] $ProtectedVolume = 'C:'
)

$ErrorActionPreference = 'Stop'
$vmName = 'SetnessJenkinsPilot'
$vmRoot = Join-Path $ProtectedVolume 'ProgramData\SetnessConsulting\JenkinsVM'
$vmDiskPath = Join-Path $vmRoot 'ubuntu-server-24.04.vhdx'
$switchName = 'SetnessJenkinsHostOnly'
$natName = 'SetnessJenkinsNat'
$networkPrefix = '192.168.218.0/24'
$hostAddress = '192.168.218.1'
$guestAddress = '192.168.218.2'
$preflightPath = Join-Path $PSScriptRoot 'hyperv-preflight.ps1'

if (-not (Test-Path -LiteralPath $UbuntuServerIsoPath -PathType Leaf)) {
    throw 'Provide a downloaded Ubuntu Server 24.04 amd64 ISO and verify it against Canonical release checksums.'
}
$actualIsoSha256 = (Get-FileHash -LiteralPath $UbuntuServerIsoPath -Algorithm SHA256).Hash
if (-not $actualIsoSha256.Equals($UbuntuIsoSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The Ubuntu ISO checksum does not match the independently verified Canonical checksum. No VM or network was created.'
}

& $preflightPath -ProtectedVolume $ProtectedVolume

if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    throw "A VM named $vmName already exists. This script never overwrites or deletes VM state."
}
if (Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue) {
    throw "A switch named $switchName already exists. Inspect it before proceeding; this script will not reuse or modify it."
}
if (Get-NetNat -Name $natName -ErrorAction SilentlyContinue) {
    throw "A NAT named $natName already exists. Inspect it before proceeding; this script will not reuse or modify it."
}
if (@(Get-NetNat -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'A Windows NAT already exists. Hyper-V NAT coexistence has not been proven on this host; stop rather than modifying existing WSL, Docker, or VPN networking.'
}
if (Test-Path -LiteralPath $vmRoot) {
    throw "The intended VM data directory already exists: $vmRoot. Inspect it manually; this script will not overwrite or clean it."
}

function Convert-IPv4ToUInt64([string] $Address) {
    $parsed = [Net.IPAddress]::Parse($Address)
    if ($parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Expected an IPv4 address: $Address"
    }
    $bytes = $parsed.GetAddressBytes()
    [Array]::Reverse($bytes)
    return [uint64][BitConverter]::ToUInt32($bytes, 0)
}

function Get-IPv4Range([string] $Cidr) {
    $parts = $Cidr -split '/', 2
    if ($parts.Count -ne 2) { throw "Invalid IPv4 route: $Cidr" }
    $prefixLength = [int]$parts[1]
    if ($prefixLength -lt 1 -or $prefixLength -gt 32) { throw "Invalid IPv4 route: $Cidr" }
    $addressValue = Convert-IPv4ToUInt64 $parts[0]
    $size = [uint64][math]::Pow(2, 32 - $prefixLength)
    $networkValue = [uint64]([math]::Floor($addressValue / $size) * $size)
    return [pscustomobject]@{ Start = $networkValue; End = ($networkValue + $size - 1) }
}

$candidateRange = Get-IPv4Range $networkPrefix
$existingPrefixes = @(
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }
    Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.DestinationPrefix -ne '0.0.0.0/0' } |
        ForEach-Object { $_.DestinationPrefix }
) | Select-Object -Unique
foreach ($prefix in $existingPrefixes) {
    try { $range = Get-IPv4Range $prefix } catch { continue }
    if ($candidateRange.Start -le $range.End -and $range.Start -le $candidateRange.End) {
        throw "The proposed VM network $networkPrefix overlaps an existing host route or interface ($prefix). No VM was created."
    }
}

$hostVnic = "vEthernet ($switchName)"
$createdRoot = $false
$createdSwitch = $false
$createdAddress = $false
$createdNat = $false
$createdDisk = $false
$createdVm = $false

try {
    New-Item -ItemType Directory -Path $vmRoot | Out-Null
    $createdRoot = $true
    New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
    $createdSwitch = $true
    New-NetIPAddress -InterfaceAlias $hostVnic -IPAddress $hostAddress -PrefixLength 24 | Out-Null
    $createdAddress = $true
    New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $networkPrefix | Out-Null
    $createdNat = $true

    New-VHD -Path $vmDiskPath -SizeBytes 120GB -Dynamic | Out-Null
    $createdDisk = $true
    New-VM `
        -Name $vmName `
        -Path $vmRoot `
        -Generation 2 `
        -MemoryStartupBytes 16GB `
        -VHDPath $vmDiskPath `
        -SwitchName $switchName | Out-Null
    $createdVm = $true
    Set-VMProcessor -VMName $vmName -Count 8
    Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
    Set-VM -Name $vmName -AutomaticStartAction Start -AutomaticStopAction ShutDown -AutomaticCheckpointsEnabled $false
    Add-VMDvdDrive -VMName $vmName -Path (Resolve-Path -LiteralPath $UbuntuServerIsoPath).Path | Out-Null
    $dvd = Get-VMDvdDrive -VMName $vmName
    Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd
    Start-VM -Name $vmName | Out-Null
}
catch {
    $creationError = $_
    $rollbackIssues = [System.Collections.Generic.List[string]]::new()

    if ($createdVm) {
        try {
            $partialVm = Get-VM -Name $vmName -ErrorAction Stop
            if ($partialVm.State -ne 'Off') {
                Stop-VM -Name $vmName -Force -Confirm:$false -ErrorAction Stop | Out-Null
            }
            Remove-VM -Name $vmName -Force -Confirm:$false -ErrorAction Stop
        }
        catch { $rollbackIssues.Add("VM registration: $($_.Exception.Message)") }
    }
    if ($createdDisk -and (Test-Path -LiteralPath $vmDiskPath -PathType Leaf)) {
        try {
            $resolvedRoot = [IO.Path]::GetFullPath($vmRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $resolvedDisk = [IO.Path]::GetFullPath($vmDiskPath)
            if (-not $resolvedDisk.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'The generated VHDX path escaped the intended VM directory.'
            }
            Remove-VHD -Path $resolvedDisk -ErrorAction Stop
        }
        catch { $rollbackIssues.Add("VHDX: $($_.Exception.Message)") }
    }
    if ($createdNat) {
        try {
            $partialNat = Get-NetNat -Name $natName -ErrorAction Stop
            if ($partialNat.InternalIPInterfaceAddressPrefix -ne $networkPrefix) {
                throw 'The NAT no longer matches the exact prefix created by this script.'
            }
            Remove-NetNat -Name $natName -Confirm:$false -ErrorAction Stop
        }
        catch { $rollbackIssues.Add("NAT: $($_.Exception.Message)") }
    }
    if ($createdAddress) {
        try {
            $partialAddress = Get-NetIPAddress -InterfaceAlias $hostVnic -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -eq $hostAddress -and $_.PrefixLength -eq 24 }
            if ($partialAddress) {
                $partialAddress | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
            }
        }
        catch { $rollbackIssues.Add("Host-only address: $($_.Exception.Message)") }
    }
    if ($createdSwitch) {
        try {
            $partialSwitch = Get-VMSwitch -Name $switchName -ErrorAction Stop
            if ($partialSwitch.SwitchType -ne 'Internal') {
                throw 'The switch is no longer an internal switch.'
            }
            Remove-VMSwitch -Name $switchName -Force -Confirm:$false -ErrorAction Stop
        }
        catch { $rollbackIssues.Add("Hyper-V switch: $($_.Exception.Message)") }
    }
    if ($createdRoot -and (Test-Path -LiteralPath $vmRoot -PathType Container)) {
        try {
            if (@(Get-ChildItem -LiteralPath $vmRoot -Force -ErrorAction Stop).Count -eq 0) {
                Remove-Item -LiteralPath $vmRoot -Force -ErrorAction Stop
            }
            else {
                $rollbackIssues.Add('VM directory was retained because it contains files; inspect it manually.')
            }
        }
        catch { $rollbackIssues.Add("VM directory: $($_.Exception.Message)") }
    }

    $rollbackSummary = if ($rollbackIssues.Count -eq 0) { 'Rollback of resources created by this invocation completed.' } else { "Rollback needs inspection: $($rollbackIssues -join '; ')" }
    throw "VM provisioning failed: $($creationError.Exception.Message) $rollbackSummary"
}

Write-Output "Created and started $vmName with 8 vCPU, 16 GiB RAM, and a 120 GiB dynamically expanding VHDX under the BitLocker-protected $ProtectedVolume volume."
Write-Output "Host-only network: $networkPrefix; Windows host: $hostAddress; Ubuntu guest static address: $guestAddress."
Write-Output 'Install Ubuntu Server 24.04 in VMConnect. Configure the NIC as guestAddress/24, gateway hostAddress, DNS 1.1.1.1; install OpenSSH only if needed for guest administration.'
Write-Output 'No GitHub credential, Jenkins volume, port forward, or firewall rule was moved or changed by this script.'
