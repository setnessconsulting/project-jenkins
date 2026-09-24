[CmdletBinding()]
param(
    [ValidateSet('start', 'stop', 'restart', 'status', 'logs')]
    [string] $Action = 'start'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'pilot-config.ps1')
$null = Get-JenkinsPilotConfig -RepositoryRoot $repositoryRoot
$stateDirectory = Join-Path $env:LOCALAPPDATA 'SetnessConsulting\JenkinsPilot'
$encryptedPasswordPath = Join-Path $stateDirectory 'admin-password.dpapi'
$encryptedAgentSecretPath = Join-Path $stateDirectory 'agent-secret.dpapi'

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
    $userAce = "*$userSid`:(OI)(CI)F"
    $systemAce = '*S-1-5-18:(OI)(CI)F'
    & icacls.exe $Path /inheritance:r /grant:r $userAce $systemAce | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not restrict the local Jenkins state directory ACL.'
    }
}

function Initialize-AdminCredential {
    if (-not (Test-Path -LiteralPath $stateDirectory)) {
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    }
    Set-PrivateDirectoryAcl -Path $stateDirectory

    if (Test-Path -LiteralPath $encryptedPasswordPath) {
        return
    }

    $randomBytes = New-Object byte[] 48
    $randomGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $randomGenerator.GetBytes($randomBytes)
        $generatedPassword = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $securePassword = ConvertTo-SecureString -String $generatedPassword -AsPlainText -Force
        ConvertFrom-SecureString -SecureString $securePassword |
            Set-Content -LiteralPath $encryptedPasswordPath -Encoding Ascii -NoNewline
    }
    finally {
        [Array]::Clear($randomBytes, 0, $randomBytes.Length)
        if ($randomGenerator) { $randomGenerator.Dispose() }
        if ($securePassword) { $securePassword.Dispose() }
        $generatedPassword = $null
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker Desktop CLI is not available. Start Docker Desktop and retry.'
}

if ($Action -in @('status', 'logs', 'stop')) {
    # Compose requires these values to render its model even for read-only or
    # stop operations. This placeholder is never passed to a running service.
    $env:JENKINS_ADMIN_ID = 'jenkins-admin'
    $env:JENKINS_ADMIN_PASSWORD = 'compose-inspection-only'
    $env:JENKINS_HTTP_PORT = '18080'
    $composeArgs = @()
    switch ($Action) {
        'stop' { $composeArgs += 'stop' }
        'status' { $composeArgs += 'ps' }
        'logs' { $composeArgs += @('logs', '--tail', '100') }
    }
    try {
        & docker compose --project-directory $repositoryRoot @composeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Docker Compose $Action failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Remove-Item Env:\JENKINS_ADMIN_ID, Env:\JENKINS_ADMIN_PASSWORD, Env:\JENKINS_HTTP_PORT -ErrorAction SilentlyContinue
    }
    return
}

if ($Action -eq 'start') {
    Initialize-AdminCredential
}
elseif (-not (Test-Path -LiteralPath $encryptedPasswordPath)) {
    throw 'Jenkins has not been initialized. Run start before restart.'
}

$encryptedPassword = Get-Content -LiteralPath $encryptedPasswordPath -Raw
$securePassword = ConvertTo-SecureString -String $encryptedPassword
$env:JENKINS_ADMIN_ID = 'jenkins-admin'
$env:JENKINS_ADMIN_PASSWORD = Convert-SecureStringToPlainText $securePassword
$env:JENKINS_HTTP_PORT = '18080'
$agentSecret = $null
$secureAgentSecret = $null
$hasAgentSecret = Test-Path -LiteralPath $encryptedAgentSecretPath

if ($hasAgentSecret) {
    $encryptedAgentSecret = Get-Content -LiteralPath $encryptedAgentSecretPath -Raw
    $secureAgentSecret = ConvertTo-SecureString -String $encryptedAgentSecret
    $agentSecret = Convert-SecureStringToPlainText $secureAgentSecret
    $env:JENKINS_AGENT_SECRET = $agentSecret
}

try {
    if ($Action -eq 'start') {
        $composeArgs = @('up', '--build', '--detach', 'controller')
        if ($hasAgentSecret) { $composeArgs += 'agent' }
    }
    else {
        # `docker compose restart` only restarts existing containers; it does
        # not apply changed environment, mounts, image builds, or service
        # definitions. Recreate the services while retaining the named
        # Jenkins volume so checked-in CasC and ignored local wiring take effect.
        $composeArgs = @('up', '--build', '--detach', '--force-recreate', 'controller')
        if ($hasAgentSecret) { $composeArgs += 'agent' }
    }

    & docker compose --project-directory $repositoryRoot @composeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose $Action failed with exit code $LASTEXITCODE."
    }
}
finally {
    Remove-Item Env:\JENKINS_ADMIN_ID, Env:\JENKINS_ADMIN_PASSWORD, Env:\JENKINS_HTTP_PORT, Env:\JENKINS_AGENT_SECRET -ErrorAction SilentlyContinue
    $env:JENKINS_ADMIN_PASSWORD = $null
    $env:JENKINS_AGENT_SECRET = $null
    $agentSecret = $null
    $securePassword.Dispose()
    if ($secureAgentSecret) { $secureAgentSecret.Dispose() }
}

if ($Action -eq 'start') {
    if ($hasAgentSecret) {
        Write-Output 'Jenkins controller and enrolled agent are starting. Check status before using the pilot.'
    }
    else {
        Write-Output 'Jenkins controller is starting. After it is ready, run .\scripts\enroll-agent.ps1 to enroll the private-network agent.'
    }
    Write-Output 'The random administrator credential is DPAPI-protected outside the repository; use scripts/show-admin-password.ps1 locally if you need to sign in to the UI.'
}
else {
    Write-Output 'Jenkins services were restarted. Check status before using the pilot.'
}
