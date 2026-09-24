[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$encryptedPasswordPath = Join-Path $env:LOCALAPPDATA 'SetnessConsulting\JenkinsPilot\admin-password.dpapi'
if (-not (Test-Path -LiteralPath $encryptedPasswordPath)) {
    throw 'The local Jenkins administrator password has not been initialized.'
}

$securePassword = ConvertTo-SecureString -String (Get-Content -LiteralPath $encryptedPasswordPath -Raw)
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $securePassword.Dispose()
}
