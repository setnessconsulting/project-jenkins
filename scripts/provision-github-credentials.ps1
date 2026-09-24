[CmdletBinding()]
param(
    [string] $AppKeyPath
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'pilot-config.ps1')
$pilotConfig = Get-JenkinsPilotConfig -RepositoryRoot $repositoryRoot
$stateDirectory = Join-Path $env:LOCALAPPDATA 'SetnessConsulting\JenkinsPilot'
$encryptedAdminPasswordPath = Join-Path $stateDirectory 'admin-password.dpapi'
$encryptedDeployKeyPath = Join-Path $stateDirectory "$($pilotConfig.Repository)-deploy-key.dpapi"
$encryptedAppKeyPath = Join-Path $stateDirectory 'github-app-private-key.dpapi'
$controllerUrl = 'http://127.0.0.1:18080'
$appId = $pilotConfig.AppId
$appCredentialId = 'setness-jenkins-app'
$sshCredentialId = 'setness-jenkins-readonly-checkout'
$targetRepository = $pilotConfig.FullName

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
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $userAce = "*${userSid}:(OI)(CI)F"
    $systemAce = '*S-1-5-18:(OI)(CI)F'
    & icacls.exe $Path /inheritance:r /grant:r $userAce $systemAce | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not restrict the local Jenkins state directory ACL.'
    }
}

Set-PrivateDirectoryAcl -Path $stateDirectory
if (-not (Test-Path -LiteralPath $encryptedAdminPasswordPath) -or
    -not (Test-Path -LiteralPath $encryptedDeployKeyPath)) {
    throw 'Initialize the controller and add the read-only deploy key first.'
}

if (-not $AppKeyPath) {
    $downloadDirectory = Join-Path $env:USERPROFILE 'Downloads'
    $appKeyCandidate = Get-ChildItem -LiteralPath $downloadDirectory -Filter '*jenkins*.private-key.pem' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $appKeyCandidate) {
        throw 'The downloaded Jenkins GitHub App private key was not found in Downloads. Supply -AppKeyPath.'
    }
    $AppKeyPath = $appKeyCandidate.FullName
}
if (-not (Test-Path -LiteralPath $AppKeyPath -PathType Leaf)) {
    throw 'The GitHub App key path does not exist.'
}

$encryptedAdminPassword = Get-Content -LiteralPath $encryptedAdminPasswordPath -Raw
$secureAdminPassword = ConvertTo-SecureString -String $encryptedAdminPassword
$adminPassword = Convert-SecureStringToPlainText $secureAdminPassword
$adminUser = 'jenkins-admin'
$basicToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${adminUser}:$adminPassword"))
$headers = @{ Authorization = "Basic $basicToken" }
$rsa = [System.Security.Cryptography.RSA]::Create()
$appPrivateKeyPem = $null
$deployPrivateKey = $null
$secureDeployKey = $null
$secureAppKey = $null
$privateKeyBytes = $null

try {
    $sourceAppKey = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $AppKeyPath).Path)
    $rsa.ImportFromPem($sourceAppKey)
    $privateKeyBytes = $rsa.ExportPkcs8PrivateKey()
    $encodedAppKey = [Convert]::ToBase64String($privateKeyBytes, [Base64FormattingOptions]::InsertLineBreaks)
    $appPrivateKeyPem = "-----BEGIN PRIVATE KEY-----`n$encodedAppKey`n-----END PRIVATE KEY-----"
    [Array]::Clear($privateKeyBytes, 0, $privateKeyBytes.Length)
    $privateKeyBytes = $null
    $sourceAppKey = $null
    $encodedAppKey = $null

    $encryptedDeployKey = Get-Content -LiteralPath $encryptedDeployKeyPath -Raw
    $secureDeployKey = ConvertTo-SecureString -String $encryptedDeployKey
    $deployPrivateKey = Convert-SecureStringToPlainText $secureDeployKey
    $encryptedDeployKey = $null

    # Retain a DPAPI-protected local recovery copy. The Jenkins credential store
    # also encrypts the App key in the persistent Jenkins home.
    $secureAppKey = ConvertTo-SecureString -String $appPrivateKeyPem -AsPlainText -Force
    ConvertFrom-SecureString -SecureString $secureAppKey |
        Set-Content -LiteralPath $encryptedAppKeyPath -Encoding Ascii -NoNewline
    $appKeyRoundTrip = ConvertTo-SecureString -String (Get-Content -LiteralPath $encryptedAppKeyPath -Raw)
    $appKeyRoundTripText = Convert-SecureStringToPlainText $appKeyRoundTrip
    if ($appKeyRoundTripText -ne $appPrivateKeyPem) {
        throw 'The local DPAPI recovery copy did not pass its verification check.'
    }
    $appKeyRoundTrip.Dispose()
    $appKeyRoundTripText = $null

    $jenkinsSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $crumb = Invoke-RestMethod `
        -Uri "$controllerUrl/crumbIssuer/api/json" `
        -Headers $headers `
        -WebSession $jenkinsSession `
        -TimeoutSec 15
    if (-not $crumb.crumb -or -not $crumb.crumbRequestField) {
        throw 'Jenkins did not return the expected CSRF protection token.'
    }
    $headers[$crumb.crumbRequestField] = $crumb.crumb

    $appKeyForGroovy = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($appPrivateKeyPem))
    $deployKeyForGroovy = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($deployPrivateKey))
    $groovy = @"
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey
import hudson.util.Secret
import org.jenkinsci.plugins.github_branch_source.Connector
import org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials
import org.jenkinsci.plugins.github_branch_source.app_credentials.AccessSpecifiedRepositories
import org.jenkinsci.plugins.github_branch_source.app_credentials.DefaultPermissionsStrategy
import java.nio.charset.StandardCharsets
import java.util.Base64

def appKey = new String(Base64.decoder.decode('$appKeyForGroovy'), StandardCharsets.UTF_8)
def sshKey = new String(Base64.decoder.decode('$deployKeyForGroovy'), StandardCharsets.UTF_8)
def provider = SystemCredentialsProvider.getInstance()
def store = provider.getStore()
def domain = Domain.global()
def credentials = store.getCredentials(domain)
def appId = '$appCredentialId'
def sshId = '$sshCredentialId'
def appCredential = credentials.find { it.id == appId }
def sshCredential = credentials.find { it.id == sshId }

if (appCredential != null && !(appCredential instanceof GitHubAppCredentials)) {
    throw new IllegalStateException('The App credential ID is already occupied by another credential type.')
}
if (appCredential != null && (appCredential.getAppID() != '$appId' ||
        appCredential.getPrivateKey().getPlainText().replace('\r\n', '\n').trim() != appKey.replace('\r\n', '\n').trim())) {
    throw new IllegalStateException('A different GitHub App key is already stored under the pilot credential ID.')
}
if (appCredential == null) {
    appCredential = new GitHubAppCredentials(
        CredentialsScope.GLOBAL, appId, 'Controller-only GitHub App for pilot discovery and Checks',
        '$appId', Secret.fromString(appKey))
}
appCredential.setRepositoryAccessStrategy(
    new AccessSpecifiedRepositories('$($pilotConfig.Owner)', ['$($pilotConfig.Repository)']))
appCredential.setDefaultPermissionsStrategy(DefaultPermissionsStrategy.INHERIT_ALL)

if (sshCredential != null && !(sshCredential instanceof BasicSSHUserPrivateKey)) {
    throw new IllegalStateException('The checkout credential ID is already occupied by another credential type.')
}
if (sshCredential != null && (sshCredential.getUsername() != 'git' ||
        !sshCredential.getPrivateKeys().contains(sshKey))) {
    throw new IllegalStateException('A different SSH key is already stored under the pilot checkout credential ID.')
}
if (sshCredential == null) {
    sshCredential = new BasicSSHUserPrivateKey(
        CredentialsScope.GLOBAL, sshId, 'git',
        new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(sshKey), null,
        'Separate read-only checkout deploy key')
}

if (credentials.find { it.id == appId } == null && !store.addCredentials(domain, appCredential)) {
    throw new IllegalStateException('Jenkins could not save the GitHub App credential.')
}
if (credentials.find { it.id == sshId } == null && !store.addCredentials(domain, sshCredential)) {
    throw new IllegalStateException('Jenkins could not save the read-only checkout credential.')
}
provider.save()

def connection = Connector.connect('https://api.github.com', appCredential)
try {
    def actualRepository = connection.getRepository('$targetRepository').getFullName()
    if (!actualRepository.equalsIgnoreCase('$targetRepository')) {
        throw new IllegalStateException('The App credential authenticated to an unexpected repository.')
    }
} finally {
    Connector.release(connection)
}

println 'PILOT_GITHUB_CREDENTIALS_CONFIGURED'
"@

    $requestBody = @{ script = $groovy }
    try {
        $response = Invoke-WebRequest `
            -Uri "$controllerUrl/scriptText" `
            -Method Post `
            -Headers $headers `
            -WebSession $jenkinsSession `
            -Body $requestBody `
            -ContentType 'application/x-www-form-urlencoded' `
            -UseBasicParsing `
            -TimeoutSec 30
    }
    catch {
        throw 'Jenkins credential provisioning failed. The response body was suppressed to protect credential material.'
    }
    if ($response.Content.Trim() -ne 'PILOT_GITHUB_CREDENTIALS_CONFIGURED') {
        throw 'Jenkins did not confirm both credentials and the App repository-access test.'
    }
}
finally {
    $rsa.Dispose()
    if ($secureAdminPassword) { $secureAdminPassword.Dispose() }
    if ($secureDeployKey) { $secureDeployKey.Dispose() }
    if ($secureAppKey) { $secureAppKey.Dispose() }
    if ($privateKeyBytes) { [Array]::Clear($privateKeyBytes, 0, $privateKeyBytes.Length) }
    $appPrivateKeyPem = $null
    $deployPrivateKey = $null
    $adminPassword = $null
    $basicToken = $null
    $groovy = $null
    $appKeyForGroovy = $null
    $deployKeyForGroovy = $null
    $requestBody = $null
    $headers = $null
    $jenkinsSession = $null
}

Write-Output 'Jenkins stored the repo-scoped GitHub App credential and the separate read-only SSH checkout credential. The App key stays on the controller; repository checkout uses the deploy key.'
