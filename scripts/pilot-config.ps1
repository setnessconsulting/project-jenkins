function Get-JenkinsPilotConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    $configPath = Join-Path $RepositoryRoot '.env'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw 'Local pilot configuration is missing. Copy .env.example to .env and fill in the target-specific values.'
    }

    $values = @{}
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $configPath) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }
        if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            throw "Invalid local pilot configuration syntax on line $lineNumber."
        }

        $name = $Matches[1]
        $value = $Matches[2].Trim()
        if ($values.ContainsKey($name)) {
            throw "Duplicate local pilot configuration key on line $lineNumber."
        }
        if ($value.Length -ge 2 -and
            (($value.StartsWith('"') -and $value.EndsWith('"')) -or
             ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$name] = $value
    }

    foreach ($requiredName in @(
        'JENKINS_TARGET_REPO_OWNER',
        'JENKINS_TARGET_REPO_NAME',
        'JENKINS_GITHUB_APP_ID',
        'JENKINS_MULTIBRANCH_JOB_NAME',
        'JENKINS_MARKER_FILE',
        'JENKINS_CANDIDATE_PATHS'
    )) {
        if (-not $values.ContainsKey($requiredName) -or [string]::IsNullOrWhiteSpace($values[$requiredName])) {
            throw "Required local pilot configuration key is missing: $requiredName."
        }
    }

    $owner = [string] $values['JENKINS_TARGET_REPO_OWNER']
    $repository = [string] $values['JENKINS_TARGET_REPO_NAME']
    $appId = [string] $values['JENKINS_GITHUB_APP_ID']
    $appCredentialId = if ($values.ContainsKey('JENKINS_GITHUB_APP_CREDENTIAL_ID')) {
        [string] $values['JENKINS_GITHUB_APP_CREDENTIAL_ID']
    }
    else {
        'github-app'
    }
    $checkoutCredentialId = if ($values.ContainsKey('JENKINS_CHECKOUT_SSH_CREDENTIAL_ID')) {
        [string] $values['JENKINS_CHECKOUT_SSH_CREDENTIAL_ID']
    }
    else {
        'jenkins-readonly-checkout'
    }
    $jobName = [string] $values['JENKINS_MULTIBRANCH_JOB_NAME']
    $markerFile = [string] $values['JENKINS_MARKER_FILE']
    if ($owner -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$') {
        throw 'The configured GitHub owner name is invalid.'
    }
    if ($repository -notmatch '^[A-Za-z0-9._-]{1,100}$') {
        throw 'The configured GitHub repository name is invalid.'
    }
    if ($appId -notmatch '^\d+$') {
        throw 'The configured GitHub App ID must contain digits only.'
    }
    if ($appCredentialId -notmatch '^[A-Za-z0-9._-]{1,100}$') {
        throw 'The configured GitHub App credential ID is invalid.'
    }
    if ($checkoutCredentialId -notmatch '^[A-Za-z0-9._-]{1,100}$') {
        throw 'The configured read-only checkout credential ID is invalid.'
    }
    if ($checkoutCredentialId -eq $appCredentialId) {
        throw 'The GitHub App and read-only checkout credentials must use separate credential IDs.'
    }
    if ($jobName -notmatch '^[A-Za-z0-9._-]{1,100}$') {
        throw 'The configured Jenkins multibranch job name is invalid.'
    }
    if ($markerFile -notmatch '^[A-Za-z0-9._/-]+$' -or
        $markerFile.StartsWith('/') -or
        $markerFile -match '(^|/)\.\.?(/|$)') {
        throw 'The configured marker file must be a relative repository path.'
    }

    $candidatePaths = @($values['JENKINS_CANDIDATE_PATHS'] -split ',' | ForEach-Object { $_.Trim() })
    $invalidCandidatePaths = @($candidatePaths | Where-Object {
        $_ -notmatch '^[A-Za-z0-9._/-]+$' -or
        $_.StartsWith('/') -or
        $_ -match '(^|/)\.\.?(/|$)'
    })
    if ($candidatePaths.Count -eq 0 -or $invalidCandidatePaths.Count -gt 0) {
        throw 'Candidate path rules must be comma-separated relative path prefixes or exact paths.'
    }
    if (@($candidatePaths | Select-Object -Unique).Count -ne $candidatePaths.Count) {
        throw 'Candidate path rules must not contain duplicates.'
    }

    [pscustomobject]@{
        Owner = $owner
        Repository = $repository
        FullName = "$owner/$repository"
        AppId = $appId
        AppCredentialId = $appCredentialId
        CheckoutCredentialId = $checkoutCredentialId
        JobName = $jobName
        MarkerFile = $markerFile
        CandidatePaths = $candidatePaths
    }
}
