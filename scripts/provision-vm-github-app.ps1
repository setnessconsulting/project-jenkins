[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) '.env'),
    [string] $ControllerUrl = 'http://127.0.0.1:18080',
    [ValidatePattern('^[A-Za-z]:$')]
    [string] $ProtectedVolume = 'C:'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'pilot-config.ps1')

$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'App key provisioning requires elevated host preflight. No credential was sent.'
}
& (Join-Path $PSScriptRoot 'hyperv-preflight.ps1') -ProtectedVolume $ProtectedVolume

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw 'The ignored local .env file was not found. Pass -ConfigPath to its preserved local location; never copy it into tracked files.'
}
if ([IO.Path]::GetFileName($ConfigPath) -ne '.env') {
    throw 'ConfigPath must identify the ignored local .env file.'
}
$pilotConfig = Get-JenkinsPilotConfig -RepositoryRoot (Split-Path -LiteralPath $ConfigPath -Parent)

$controllerUri = [Uri] $ControllerUrl
if ($controllerUri.Scheme -ne 'http' -or -not $controllerUri.IsLoopback -or
    $controllerUri.Port -ne 18080 -or
    $controllerUri.AbsolutePath -ne '/') {
    throw 'App credentials may only be provisioned through the Windows loopback-only Jenkins forward.'
}

$vm = Get-VM -Name 'SetnessJenkinsPilot' -ErrorAction SilentlyContinue
if (-not $vm -or $vm.State -ne 'Running') {
    throw 'The dedicated protected Hyper-V Jenkins VM must be running before App credentials can move.'
}
$forwardReadback = @(netsh interface portproxy show v4tov4)
if (-not ($forwardReadback | Where-Object { $_ -match '^\s*127\.0\.0\.1\s+18080\s+192\.168\.218\.2\s+18080\s*$' })) {
    throw 'The expected loopback-only Windows-to-VM forward was not read back. No credential was sent.'
}

$stateDirectory = Join-Path $env:LOCALAPPDATA 'SetnessConsulting\JenkinsPilot'
$encryptedAppKeyPath = Join-Path $stateDirectory 'github-app-private-key.dpapi'
if (-not (Test-Path -LiteralPath $encryptedAppKeyPath -PathType Leaf)) {
    throw 'The existing DPAPI-protected GitHub App recovery key was not found. Do not re-download or move a key until the host encryption preflight passes.'
}

function Convert-SecureStringToPlainText([System.Security.SecureString] $Value) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

$adminSecurePassword = Read-Host 'Enter the new VM Jenkins bootstrap administrator password' -AsSecureString
$adminPassword = $null
$basicToken = $null
$appPrivateKeyPem = $null
$privateKeyBytes = $null
$encodedAppKey = $null
$groovy = $null
$headers = $null
$jenkinsSession = $null
$secureAppKey = $null
$rsa = [System.Security.Cryptography.RSA]::Create()

try {
    $adminPassword = Convert-SecureStringToPlainText $adminSecurePassword
    if ([string]::IsNullOrWhiteSpace($adminPassword)) {
        throw 'The Jenkins administrator password cannot be empty.'
    }
    $basicToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("jenkins-admin:$adminPassword"))
    $headers = @{ Authorization = "Basic $basicToken" }

    $encryptedAppKey = Get-Content -LiteralPath $encryptedAppKeyPath -Raw
    $secureAppKey = ConvertTo-SecureString -String $encryptedAppKey
    $appPrivateKeyPem = Convert-SecureStringToPlainText $secureAppKey
    $rsa.ImportFromPem($appPrivateKeyPem)
    $privateKeyBytes = $rsa.ExportPkcs8PrivateKey()
    $encodedAppKey = [Convert]::ToBase64String($privateKeyBytes)
    [Array]::Clear($privateKeyBytes, 0, $privateKeyBytes.Length)
    $privateKeyBytes = $null

    $jenkinsSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $crumb = Invoke-RestMethod `
        -Uri "$($controllerUri.AbsoluteUri.TrimEnd('/'))/crumbIssuer/api/json" `
        -Headers $headers `
        -WebSession $jenkinsSession `
        -TimeoutSec 15
    if (-not $crumb.crumb -or -not $crumb.crumbRequestField) {
        throw 'Jenkins did not return the expected CSRF protection token.'
    }
    $headers[$crumb.crumbRequestField] = $crumb.crumb

    $appCredentialId = $pilotConfig.AppCredentialId
    $targetRepository = $pilotConfig.FullName
    $appId = $pilotConfig.AppId
    $owner = $pilotConfig.Owner
    $repository = $pilotConfig.Repository

    $groovy = @"
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import hudson.util.Secret
import org.jenkinsci.plugins.github_branch_source.Connector
import org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials
import org.jenkinsci.plugins.github_branch_source.app_credentials.AccessSpecifiedRepositories
import org.jenkinsci.plugins.github_branch_source.app_credentials.DefaultPermissionsStrategy
import java.nio.charset.StandardCharsets
import java.util.Base64

def appKey = new String(Base64.decoder.decode('$encodedAppKey'), StandardCharsets.UTF_8)
def provider = SystemCredentialsProvider.getInstance()
def store = provider.getStore()
def domain = Domain.global()
def credentials = store.getCredentials(domain)
def credentialId = '$appCredentialId'
def existing = credentials.find { it.id == credentialId }

if (existing != null && !(existing instanceof GitHubAppCredentials)) {
    throw new IllegalStateException('The App credential ID is occupied by an unexpected credential type.')
}
if (existing != null && (existing.getAppID() != '$appId' ||
        existing.getPrivateKey().getPlainText().replace('\\r\\n', '\\n').trim() != appKey.replace('\\r\\n', '\\n').trim())) {
    throw new IllegalStateException('A different App key is already stored under the pilot credential ID.')
}
if (existing == null) {
    existing = new GitHubAppCredentials(
        CredentialsScope.GLOBAL, credentialId, 'Controller-only GitHub App for discovery and Checks',
        '$appId', Secret.fromString(appKey))
    if (!store.addCredentials(domain, existing)) {
        throw new IllegalStateException('Jenkins could not save the GitHub App credential.')
    }
}
existing.setRepositoryAccessStrategy(new AccessSpecifiedRepositories('$owner', ['$repository']))
existing.setDefaultPermissionsStrategy(DefaultPermissionsStrategy.CONTENTS_READ)
provider.save()

def connection = Connector.connect('https://api.github.com', existing)
try {
    def actualRepository = connection.getRepository('$targetRepository').getFullName()
    if (!actualRepository.equalsIgnoreCase('$targetRepository')) {
        throw new IllegalStateException('The App authenticated to an unexpected repository.')
    }
} finally {
    Connector.release(connection)
}
println 'PILOT_VM_GITHUB_APP_CONFIGURED'
"@

    try {
        $response = Invoke-WebRequest `
            -Uri "$($controllerUri.AbsoluteUri.TrimEnd('/'))/scriptText" `
            -Method Post `
            -Headers $headers `
            -WebSession $jenkinsSession `
            -Body @{ script = $groovy } `
            -ContentType 'application/x-www-form-urlencoded' `
            -UseBasicParsing `
            -TimeoutSec 30
    }
    catch {
        throw 'Jenkins App provisioning failed. The response body was suppressed to protect credential material.'
    }
    if ($response.Content.Trim() -ne 'PILOT_VM_GITHUB_APP_CONFIGURED') {
        throw 'Jenkins did not confirm the repo-scoped App credential and repository readback.'
    }
}
finally {
    $rsa.Dispose()
    if ($adminSecurePassword) { $adminSecurePassword.Dispose() }
    if ($secureAppKey) { $secureAppKey.Dispose() }
    if ($privateKeyBytes) { [Array]::Clear($privateKeyBytes, 0, $privateKeyBytes.Length) }
    $adminPassword = $null
    $basicToken = $null
    $appPrivateKeyPem = $null
    $encodedAppKey = $null
    $groovy = $null
    $headers = $null
    $jenkinsSession = $null
}

Write-Output 'Jenkins stored and validated the repository-scoped App credential; untrusted use is restricted to Contents read.'
