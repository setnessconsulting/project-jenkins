[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]:$')]
    [string] $ProtectedVolume = 'C:'
)

$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Hyper-V and BitLocker preflight requires an elevated Administrator PowerShell. No host changes were made.'
}

$failures = [System.Collections.Generic.List[string]]::new()
$hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
$hyperVManagementAvailable = [bool](Get-Command Get-VMHost -ErrorAction SilentlyContinue)
$vmms = Get-Service -Name vmms -ErrorAction SilentlyContinue

if ($hyperVFeature.State -ne 'Enabled') {
    $failures.Add('Hyper-V is not enabled; enable it and reboot only after reviewing these preflight results.')
} elseif (-not $hyperVManagementAvailable) {
    $failures.Add('Hyper-V management cmdlets are unavailable.')
} else {
    try {
        $null = Get-VMHost
    } catch {
        $failures.Add('Hyper-V host management could not be read.')
    }
}
if (-not $vmms -or $vmms.Status -ne 'Running') {
    $failures.Add('The Hyper-V Virtual Machine Management service is not running.')
}

$bitLocker = $null
try {
    $bitLocker = Get-BitLockerVolume -MountPoint $ProtectedVolume
} catch {
    $failures.Add("BitLocker state for $ProtectedVolume could not be read.")
}
$recoveryPasswordProtector = @()
if ($bitLocker) {
    if ($bitLocker.ProtectionStatus -ne 'On' -or
        $bitLocker.VolumeStatus -ne 'FullyEncrypted' -or
        $bitLocker.EncryptionPercentage -ne 100) {
        $failures.Add("The VM storage volume $ProtectedVolume is not fully encrypted and actively protected.")
    }
    $recoveryPasswordProtector = @($bitLocker.KeyProtector | Where-Object {
        $_.KeyProtectorType -eq 'RecoveryPassword'
    })
    if ($recoveryPasswordProtector.Count -eq 0) {
        $failures.Add('The protected volume has no BitLocker recovery-password protector.')
    }
} else {
    $failures.Add("No BitLocker volume information was returned for $ProtectedVolume.")
}

$computer = Get-CimInstance -ClassName Win32_ComputerSystem
$processor = Get-CimInstance -ClassName Win32_Processor |
    Measure-Object -Property NumberOfLogicalProcessors -Sum
$driveLetter = $ProtectedVolume.Substring(0, 1)
$volume = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
$minimumFreeBytes = 140GB
if ($processor.Sum -lt 8 -or $computer.TotalPhysicalMemory -lt 32GB) {
    $failures.Add('The host does not meet the minimum preflight for an 8-vCPU, 16-GiB Jenkins VM.')
}
if (-not $volume -or $volume.SizeRemaining -lt $minimumFreeBytes) {
    $failures.Add('The protected volume needs at least 140 GiB free for the VM disk, installer, and recovery space.')
}

Write-Output "Hyper-V feature: $($hyperVFeature.State); management cmdlets: $hyperVManagementAvailable; VMMS: $(if ($vmms) { $vmms.Status } else { 'unavailable' })"
if ($bitLocker) {
    Write-Output "BitLocker protection: $($bitLocker.ProtectionStatus); volume encryption: $($bitLocker.EncryptionPercentage)%; recovery-password protector present: $($recoveryPasswordProtector.Count -gt 0)"
    Write-Output 'This check does not verify recovery-key escrow; confirm the key is retrievable from its approved backup before VM creation. The key was not read or displayed.'
} else {
    Write-Output "BitLocker state: unavailable for $ProtectedVolume; no recovery key was read or displayed."
}
Write-Output "Host resources: $($processor.Sum) logical CPUs, $([math]::Round($computer.TotalPhysicalMemory / 1GB, 1)) GiB RAM, $(if ($volume) { [math]::Round($volume.SizeRemaining / 1GB, 1) } else { 'unavailable' }) GiB free on $ProtectedVolume"
if ($failures.Count -gt 0) {
    Write-Output "Preflight failed: $($failures -join ' ')"
    throw 'Host prerequisites are not yet ready. No VM, network, firewall, or credential state was changed.'
}

Write-Output 'Preflight passed. No VM, network, firewall, or credential state was changed.'
