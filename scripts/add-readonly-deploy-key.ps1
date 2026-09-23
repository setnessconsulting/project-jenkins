[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'pilot-config.ps1')
$pilotConfig = Get-JenkinsPilotConfig -RepositoryRoot $repositoryRoot
$stateDirectory = Join-Path $env:LOCALAPPDATA 'SetnessConsulting\JenkinsPilot'
$encryptedKeyPath = Join-Path $stateDirectory "$($pilotConfig.Repository)-deploy-key.dpapi"
$publicKeyPath = Join-Path $stateDirectory "$($pilotConfig.Repository)-deploy-key.pub"
$temporaryPrivateKeyPath = Join-Path $stateDirectory "$($pilotConfig.Repository)-deploy-key"
$repository = $pilotConfig.FullName
$title = 'Jenkins pilot read-only checkout'

function Convert-SecureStringToPlainText([System.Security.SecureString] $Value) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Set-PrivateDirectoryAcl([string] $Path) {
    $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $userAce = "*${userSid}:(OI)(CI)F"
    $systemAce = '*S-1-5-18:(OI)(CI)F'
    & icacls.exe $Path /inheritance:r /grant:r $userAce $systemAce | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not restrict the local Jenkins state directory ACL.'
    }
}

function Get-PublicKeyIdentity([string] $Key) {
    $parts = $Key.Trim() -split '\s+'
    if ($parts.Count -lt 2) {
        throw 'The deploy key public-key record is malformed.'
    }
    return "$($parts[0]) $($parts[1])"
}

function Get-DerivedPublicKey([string] $EncryptedPrivateKeyPath) {
    $sshKeyGen = Get-Command ssh-keygen -ErrorAction SilentlyContinue
    if (-not $sshKeyGen) {
        throw 'Windows OpenSSH ssh-keygen is not available to recover the local public-key record.'
    }

    $recoveryPath = "$temporaryPrivateKeyPath.recovery"
    if (Test-Path -LiteralPath $recoveryPath) {
        throw 'A temporary deploy-key recovery file already exists in the protected local state directory; inspect it before retrying.'
    }

    $encryptedKey = Get-Content -LiteralPath $EncryptedPrivateKeyPath -Raw
    $secureKey = ConvertTo-SecureString -String $encryptedKey
    $privateKeyText = Convert-SecureStringToPlainText $secureKey
    try {
        [IO.File]::WriteAllText($recoveryPath, $privateKeyText, [Text.UTF8Encoding]::new($false))
        $derivedKey = (& $sshKeyGen.Source -y -f $recoveryPath 2>$null | Out-String).Trim()
        $sshExitCode = $LASTEXITCODE
        if ($sshExitCode -ne 0 -or $derivedKey -notmatch '^ssh-ed25519\s+[A-Za-z0-9+/]+={0,2}(?:\s+.*)?$') {
            throw 'Could not derive a valid public key from the protected local deploy key.'
        }
        return $derivedKey
    }
    finally {
        if (Test-Path -LiteralPath $recoveryPath) {
            Remove-Item -LiteralPath $recoveryPath -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $recoveryPath) {
                throw 'Could not remove the temporary plaintext deploy-key recovery file.'
            }
        }
        $privateKeyText = $null
        $encryptedKey = $null
        if ($secureKey) { $secureKey.Dispose() }
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI is not available.'
}
if (-not (Test-Path -LiteralPath $stateDirectory)) {
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
}
Set-PrivateDirectoryAcl -Path $stateDirectory

$activeLogin = (& gh api user --jq '.login' | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $activeLogin -ne $pilotConfig.Owner) {
    throw 'Switch GitHub CLI to the owner configured in the ignored .env file and retry.'
}

$keyListJson = & gh api "repos/$repository/keys"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the target repository deploy-key list.'
}
$existingKeys = @($keyListJson | ConvertFrom-Json)
$existingKey = $existingKeys | Where-Object { $_.title -eq $title } | Select-Object -First 1

if (Test-Path -LiteralPath $encryptedKeyPath) {
    if (Test-Path -LiteralPath $publicKeyPath) {
        $publicKey = (Get-Content -LiteralPath $publicKeyPath -Raw).Trim()
    }
    else {
        $derivedPublicKey = Get-DerivedPublicKey -EncryptedPrivateKeyPath $encryptedKeyPath
        if ($existingKey) {
            if (-not $existingKey.read_only -or
                (Get-PublicKeyIdentity $existingKey.key) -ne (Get-PublicKeyIdentity $derivedPublicKey)) {
                throw 'The existing GitHub key does not match the protected local private key or is not read-only.'
            }
            $publicKey = $existingKey.key.Trim()
        }
        else {
            $publicKey = $derivedPublicKey
        }
        Set-Content -LiteralPath $publicKeyPath -Value $publicKey -Encoding Ascii -NoNewline
        $derivedPublicKey = $null
    }
}
else {
    if ($existingKey) {
        throw 'A deploy key with the pilot title already exists but its protected private key is unavailable; refusing to replace it.'
    }
    if ((Test-Path -LiteralPath $temporaryPrivateKeyPath) -or (Test-Path -LiteralPath "$temporaryPrivateKeyPath.pub")) {
        throw 'An incomplete deploy-key generation already exists in the protected local state directory; inspect it before retrying.'
    }

    $sshKeyGen = Get-Command ssh-keygen -ErrorAction SilentlyContinue
    if (-not $sshKeyGen) {
        throw 'Windows OpenSSH ssh-keygen is not available.'
    }
    & $sshKeyGen.Source -q -t ed25519 -C 'jenkins-pilot-read-only-checkout' -N '' -f $temporaryPrivateKeyPath *> $null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryPrivateKeyPath)) {
        throw 'Could not generate the local deploy key.'
    }

    $privateKeyText = Get-Content -LiteralPath $temporaryPrivateKeyPath -Raw
    $secureKey = ConvertTo-SecureString -String $privateKeyText -AsPlainText -Force
    ConvertFrom-SecureString -SecureString $secureKey |
        Set-Content -LiteralPath $encryptedKeyPath -Encoding Ascii -NoNewline
    $roundTripSecureKey = ConvertTo-SecureString -String (Get-Content -LiteralPath $encryptedKeyPath -Raw)
    $roundTripPrivateKey = Convert-SecureStringToPlainText $roundTripSecureKey
    if ($roundTripPrivateKey -ne $privateKeyText) {
        $secureKey.Dispose()
        $roundTripSecureKey.Dispose()
        throw 'The deploy key did not pass its local DPAPI protection check.'
    }
    $secureKey.Dispose()
    $roundTripSecureKey.Dispose()
    $roundTripPrivateKey = $null

    $publicKey = (Get-Content -LiteralPath "$temporaryPrivateKeyPath.pub" -Raw).Trim()
    Set-Content -LiteralPath $publicKeyPath -Value $publicKey -Encoding Ascii -NoNewline
    $privateKeyText = $null
    Remove-Item -LiteralPath $temporaryPrivateKeyPath -Force
    Remove-Item -LiteralPath "$temporaryPrivateKeyPath.pub" -Force
}

if ($existingKey) {
    if (-not $existingKey.read_only -or
        (Get-PublicKeyIdentity $existingKey.key) -ne (Get-PublicKeyIdentity $publicKey)) {
        throw 'The existing GitHub deploy key does not match the protected local key or is not read-only.'
    }
    $remoteId = [string] $existingKey.id
}
else {
    $createArgs = @(
        '-X', 'POST', "repos/$repository/keys",
        '-f', "title=$title",
        '-f', "key=$publicKey",
        '-F', 'read_only=true',
        '--jq', '{id, title, read_only}'
    )
    $created = & gh api @createArgs | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $created.read_only -or $created.title -ne $title) {
        throw 'GitHub did not confirm creation of the read-only deploy key.'
    }
    $remoteId = [string] $created.id
}

$readback = & gh api "repos/$repository/keys/$remoteId" --jq '{id, title, read_only}' | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or [string] $readback.id -ne $remoteId -or -not $readback.read_only -or $readback.title -ne $title) {
    throw 'GitHub deploy-key readback did not match the expected repository-scoped, read-only key.'
}

Write-Output "Verified read-only deploy key on $repository (key ID $remoteId). The private key is DPAPI-protected outside the repository."
