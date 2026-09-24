[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pipelinePath = Join-Path $repositoryRoot 'casc/pipelines/repository-pilot.groovy'
$composePath = Join-Path $repositoryRoot 'compose.yaml'
$jenkinsConfigPath = Join-Path $repositoryRoot 'casc/jenkins.yaml'
$jobsPath = Join-Path $repositoryRoot 'casc/jobs.groovy'
$gitIgnorePath = Join-Path $repositoryRoot '.gitignore'
$pipeline = Get-Content -LiteralPath $pipelinePath -Raw
$compose = Get-Content -LiteralPath $composePath -Raw
$jenkinsConfig = Get-Content -LiteralPath $jenkinsConfigPath -Raw
$jobs = Get-Content -LiteralPath $jobsPath -Raw
$gitIgnore = Get-Content -LiteralPath $gitIgnorePath -Raw
$lines = Get-Content -LiteralPath $pipelinePath

$environmentBlockFound = $false
$insideEnvironmentBlock = $false
foreach ($line in $lines) {
    if (-not $insideEnvironmentBlock -and $line.Trim() -eq 'environment {') {
        $environmentBlockFound = $true
        $insideEnvironmentBlock = $true
        continue
    }
    if ($insideEnvironmentBlock) {
        if ($line.Trim() -eq '}') {
            $insideEnvironmentBlock = $false
            continue
        }
        if ($line -match 'JENKINS_CLOUDFLARE_(CANDIDATE|CHANGED_PATH_COUNT|CANDIDATE_RESULT)') {
            throw 'Mutable Cloudflare Candidate state must not be declared in the Declarative environment block.'
        }
    }
}
if (-not $environmentBlockFound -or $insideEnvironmentBlock) {
    throw 'Could not safely inspect the Declarative environment block.'
}

$requiredContracts = @(
    'def candidatePathRules = /* JENKINS_PILOT_CANDIDATE_PATH_RULES */',
    'def trustedPullRequestAuthors = /* JENKINS_PILOT_TRUSTED_PR_AUTHORS */',
    'isAuthorizedPullRequestAuthor(env.CHANGE_AUTHOR, trustedPullRequestAuthors)',
    'Owner-only Jenkins shadow: PR author is not allowlisted',
    'git diff --name-only HEAD^2 HEAD',
    "assert classifyCandidateChanges([], candidatePathRules) == 'NOT_APPLICABLE'",
    "if (path.toLowerCase().endsWith('.md'))",
    'def directoryRules = candidatePathRules.findAll { rule -> rule.endsWith(''/'') }',
    'pilot-example.mdx',
    'README.md',
    "assert isAuthorizedPullRequestAuthor(trustedPullRequestAuthors[0], trustedPullRequestAuthors)",
    "assert !isAuthorizedPullRequestAuthor('untrusted-contributor', trustedPullRequestAuthors)",
    "assert !isAuthorizedPullRequestAuthor(null, trustedPullRequestAuthors)",
    "assert candidateCheckSummary('AUTHORIZED', 'NOT_APPLICABLE', 'NOT_RUN', '0') ==",
    "assert candidateCheckSummary('DENIED', 'UNCLASSIFIED', 'NOT_RUN', '0').startsWith('Not run: owner-only policy')",
    "assert candidateCheckConclusion('UNCLASSIFIED', 'NOT_RUN') == 'FAILURE'",
    "assert candidateCheckConclusion('RELEVANT', 'CANCELED') == 'CANCELED'",
    "'Not applicable: no configured Cloudflare Candidate path changed.'",
    "assert shouldFailGateClosed('RELEVANT', 'NOT_RUN', 'SUCCESS')",
    "if (shouldFailGateClosed(candidateState, candidateRunResult, currentBuild.currentResult))",
    "currentBuild.result = 'FAILURE'",
    "env.JENKINS_CLOUDFLARE_CANDIDATE = isPullRequest",
    'env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT = currentBuild.currentResult',
    "name: 'cloudflare-candidate'",
    "name: 'jenkins-pr-gate'",
    "title: 'Cloudflare Candidate (classification pending)'",
    "status: 'IN_PROGRESS'",
    'summary: gateSummary',
    'text: gateText',
    'deleteDir()',
    'throw err'
)
foreach ($contract in $requiredContracts) {
    if (-not $pipeline.Contains($contract)) {
        throw "Pipeline contract is missing required guard: $contract"
    }
}

$authorizationGuardIndex = $pipeline.IndexOf('isAuthorizedPullRequestAuthor(env.CHANGE_AUTHOR')
$candidatePendingIndex = $pipeline.IndexOf("title: 'Cloudflare Candidate (classification pending)'")
$checkoutIndex = $pipeline.IndexOf('checkout scm')
$authorizationStageIndex = $pipeline.IndexOf("stage('Authorize pull request')")
$selfTestStageIndex = $pipeline.IndexOf("stage('Pipeline policy self-test')")
if ($authorizationGuardIndex -lt 0 -or $candidatePendingIndex -lt 0 -or $checkoutIndex -lt 0 -or
    $authorizationGuardIndex -ge $candidatePendingIndex -or
    $candidatePendingIndex -ge $checkoutIndex -or
    $authorizationStageIndex -lt 0 -or $authorizationStageIndex -ge $selfTestStageIndex) {
    throw 'The trusted author allowlist must run before policy/build stages and before target checkout.'
}
if (-not $jobs.Contains("trustedAuthorsMarker = '/* JENKINS_PILOT_TRUSTED_PR_AUTHORS */'") -or
    -not $jobs.Contains('JsonOutput.toJson([targetOwner])')) {
    throw 'The trusted PR author allowlist must be injected from ignored local controller configuration.'
}
if (-not $jobs.Contains("sourceTraits.appendNode('io.jenkins.plugins.checks.github.status.GitHubSCMSourceStatusChecksTrait')") -or
    -not $jobs.Contains("gateChecks.appendNode('skip', 'false')") -or
    -not $jobs.Contains("gateChecks.appendNode('skipNotifications', 'true')")) {
    throw 'The primary check lifecycle publisher must remain enabled (including on Pipeline parse failures) without emitting legacy Status API notifications.'
}
if (-not $gitIgnore.Contains('*.env')) {
    throw 'Local environment files must be ignored by Git.'
}

if (-not $compose.Contains('127.0.0.1:${JENKINS_HTTP_PORT:-18080}:8080')) {
    throw 'The Jenkins UI must remain bound to loopback only.'
}
if (-not $jenkinsConfig.Contains('numExecutors: 0')) {
    throw 'The Jenkins controller must have zero build executors.'
}
if ($compose.Contains('docker.sock')) {
    throw 'The Compose configuration must not expose the Docker socket to a service.'
}

$agentSectionMatch = [regex]::Match($compose, '(?ms)^  agent:\r?\n(?<body>.*?)(?=^volumes:\s*$)')
if (-not $agentSectionMatch.Success) {
    throw 'Could not locate the isolated Compose agent service.'
}
$agentSection = $agentSectionMatch.Groups['body'].Value
if ($agentSection -match '(?m)^    volumes:\s*$' -or
    $agentSection.Contains('jenkins_home')) {
    throw 'The build agent must not mount controller state or host volumes.'
}
if (-not $jobs.Contains('InlineDefinitionBranchProjectFactory') -or
    -not $jobs.Contains("inlineFactory.appendNode('script', trustedPipeline)")) {
    throw 'The job must execute the checked-in trusted Pipeline, not a repository Jenkinsfile.'
}
if ([regex]::Matches($pipeline, '(?m)^\s*npm ci\s*$').Count -ne 1) {
    throw 'The trusted pipeline must install Node dependencies only once per build.'
}

Write-Output 'Repository isolation, owner-before-checkout, explicit check-reporting, and trusted-pipeline contracts passed. Jenkins also runs behavioral policy assertions before checkout on each build.'
