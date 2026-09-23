[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stateDirectory = Join-Path $env:LOCALAPPDATA 'SetnessConsulting\JenkinsPilot'
$encryptedPasswordPath = Join-Path $stateDirectory 'admin-password.dpapi'
$encryptedAgentSecretPath = Join-Path $stateDirectory 'agent-secret.dpapi'
$controllerUrl = 'http://127.0.0.1:18080'
$agentName = 'setness-linux-agent'

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

if (-not (Test-Path -LiteralPath $encryptedPasswordPath)) {
    throw 'Start the Jenkins controller first so the local administrator credential can be enrolled.'
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker Desktop CLI is not available. Start Docker Desktop and retry.'
}

$env:JENKINS_ADMIN_ID = 'jenkins-admin'
$env:JENKINS_ADMIN_PASSWORD = 'compose-inspection-only'
try {
    $runningServices = @(docker compose --project-directory $repositoryRoot ps --status running --services)
    if ($LASTEXITCODE -ne 0 -or $runningServices -notcontains 'controller') {
        throw 'The Jenkins controller is not running. Run .\scripts\start-controller.ps1 start first.'
    }
}
finally {
    Remove-Item Env:\JENKINS_ADMIN_ID, Env:\JENKINS_ADMIN_PASSWORD -ErrorAction SilentlyContinue
}

$encryptedPassword = Get-Content -LiteralPath $encryptedPasswordPath -Raw
$securePassword = ConvertTo-SecureString -String $encryptedPassword
$adminPassword = Convert-SecureStringToPlainText $securePassword
$adminId = 'jenkins-admin'
$basicToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${adminId}:$adminPassword"))
$headers = @{ Authorization = "Basic $basicToken" }
$agentSecret = $null
$secureAgentSecret = $null

try {
    $jnlpResponse = Invoke-WebRequest `
        -Uri "$controllerUrl/computer/$agentName/jenkins-agent.jnlp" `
        -Headers $headers `
        -UseBasicParsing `
        -TimeoutSec 15
    if ($jnlpResponse.Content -is [byte[]]) {
        $jnlpText = [Text.Encoding]::UTF8.GetString($jnlpResponse.Content)
    }
    else {
        $jnlpText = [string] $jnlpResponse.Content
    }
    [xml] $jnlpDocument = $jnlpText
    $arguments = @($jnlpDocument.SelectNodes("//*[local-name()='application-desc']/*[local-name()='argument']"))
    if ($arguments.Count -lt 2 -or $arguments[1].InnerText -ne $agentName) {
        throw 'Jenkins did not return the expected inbound-agent enrollment document.'
    }

    $agentSecret = $arguments[0].InnerText.Trim()
    if ($agentSecret -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'Jenkins returned an unexpected inbound-agent secret format.'
    }

    if (-not (Test-Path -LiteralPath $stateDirectory)) {
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    }
    Set-PrivateDirectoryAcl -Path $stateDirectory

    $secureAgentSecret = ConvertTo-SecureString -String $agentSecret -AsPlainText -Force
    ConvertFrom-SecureString -SecureString $secureAgentSecret |
        Set-Content -LiteralPath $encryptedAgentSecretPath -Encoding Ascii -NoNewline

    $env:JENKINS_ADMIN_ID = $adminId
    $env:JENKINS_ADMIN_PASSWORD = $adminPassword
    $env:JENKINS_HTTP_PORT = '18080'
    $env:JENKINS_AGENT_SECRET = $agentSecret
    & docker compose --project-directory $repositoryRoot up --build --detach controller agent
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose could not start the controller and agent (exit code $LASTEXITCODE)."
    }

    $online = $false
    for ($attempt = 0; $attempt -lt 45; $attempt++) {
        try {
            $nodeStatus = Invoke-RestMethod `
                -Uri "$controllerUrl/computer/$agentName/api/json?tree=offline,temporarilyOffline" `
                -Headers $headers `
                -TimeoutSec 5
            if (-not $nodeStatus.offline -and -not $nodeStatus.temporarilyOffline) {
                $online = $true
                break
            }
        }
        catch {
            # Retry while the agent container and remoting connection initialize.
        }
        Start-Sleep -Seconds 2
    }
    if (-not $online) {
        throw 'Agent container started but Jenkins did not report the agent online within 90 seconds. No builds have been scheduled; inspect local status and logs.'
    }
}
finally {
    Remove-Item Env:\JENKINS_ADMIN_ID, Env:\JENKINS_ADMIN_PASSWORD, Env:\JENKINS_HTTP_PORT, Env:\JENKINS_AGENT_SECRET -ErrorAction SilentlyContinue
    $adminPassword = $null
    $agentSecret = $null
    $basicToken = $null
    if ($securePassword) { $securePassword.Dispose() }
    if ($secureAgentSecret) { $secureAgentSecret.Dispose() }
}

Write-Output 'The inbound agent is online on the private Compose network. Its secret is DPAPI-protected outside the repository.'
Write-Output 'The agent has no published port, controller-volume mount, Docker socket, GitHub App credential, or deployment credential.'
