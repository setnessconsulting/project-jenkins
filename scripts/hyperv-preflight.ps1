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

$hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($hyperVFeature.State -ne 'Enabled') {
    throw 'Hyper-V is not enabled. This plan does not enable or substitute another runtime; stop before moving credentials.'
}
if (-not (Get-Command Get-VMHost -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V management cmdlets are unavailable. No VM can be created safely.'
}
$null = Get-VMHost
$vmms = Get-Service -Name vmms
if ($vmms.Status -ne 'Running') {
    throw 'The Hyper-V Virtual Machine Management service is not running.'
}

$bitLocker = Get-BitLockerVolume -MountPoint $ProtectedVolume
if ($bitLocker.ProtectionStatus -ne 'On' -or
    $bitLocker.VolumeStatus -ne 'FullyEncrypted' -or
    $bitLocker.EncryptionPercentage -ne 100) {
    throw "The VM storage volume $ProtectedVolume is not fully encrypted and actively protected. Stop before creating the VM or moving credentials."
}
$recoveryPasswordProtector = @($bitLocker.KeyProtector | Where-Object {
    $_.KeyProtectorType -eq 'RecoveryPassword'
})
if ($recoveryPasswordProtector.Count -eq 0) {
    throw 'The protected volume has no BitLocker recovery-password protector. Stop before creating the VM or moving credentials.'
}

$computer = Get-CimInstance -ClassName Win32_ComputerSystem
$processor = Get-CimInstance -ClassName Win32_Processor |
    Measure-Object -Property NumberOfLogicalProcessors -Sum
$driveLetter = $ProtectedVolume.Substring(0, 1)
$volume = Get-Volume -DriveLetter $driveLetter
$minimumFreeBytes = 140GB
if ($processor.Sum -lt 8 -or $computer.TotalPhysicalMemory -lt 32GB) {
    throw 'The host does not meet the minimum preflight for an 8-vCPU, 16-GiB Jenkins VM.'
}
if ($volume.SizeRemaining -lt $minimumFreeBytes) {
    throw 'The protected volume needs at least 140 GiB free for the VM disk, installer, and recovery space.'
}

Write-Output "Hyper-V: $($hyperVFeature.State); VMMS: $($vmms.Status); BitLocker protection: $($bitLocker.ProtectionStatus); volume encryption: $($bitLocker.EncryptionPercentage)%"
Write-Output 'A BitLocker recovery-password protector exists. This check does not verify escrow; confirm the recovery key is retrievable from its approved backup before VM creation. The key was not read or displayed.'
Write-Output "Host resources: $($processor.Sum) logical CPUs, $([math]::Round($computer.TotalPhysicalMemory / 1GB, 1)) GiB RAM, $([math]::Round($volume.SizeRemaining / 1GB, 1)) GiB free on $ProtectedVolume"
Write-Output 'Preflight passed. No VM, network, firewall, or credential state was changed.'
