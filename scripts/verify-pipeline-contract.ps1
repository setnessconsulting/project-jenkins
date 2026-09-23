[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pipelinePath = Join-Path $repositoryRoot 'casc/pipelines/repository-pilot.groovy'
$composePath = Join-Path $repositoryRoot 'compose.yaml'
$jenkinsConfigPath = Join-Path $repositoryRoot 'casc/jenkins.yaml'
$jobsPath = Join-Path $repositoryRoot 'casc/jobs.groovy'
$pipeline = Get-Content -LiteralPath $pipelinePath -Raw
$compose = Get-Content -LiteralPath $composePath -Raw
$jenkinsConfig = Get-Content -LiteralPath $jenkinsConfigPath -Raw
$jobs = Get-Content -LiteralPath $jobsPath -Raw
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
    "assert classifyCandidateChanges([], candidatePathRules) == 'NOT_APPLICABLE'",
    "assert candidateCheckConclusion('UNCLASSIFIED', 'NOT_RUN') == 'FAILURE'",
    "assert candidateCheckConclusion('RELEVANT', 'CANCELED') == 'CANCELED'",
    "assert shouldFailGateClosed('RELEVANT', 'NOT_RUN', 'SUCCESS')",
    "if (shouldFailGateClosed(candidateState, candidateRunResult, currentBuild.currentResult))",
    "currentBuild.result = 'FAILURE'",
    "env.JENKINS_CLOUDFLARE_CANDIDATE = isPullRequest",
    'env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT = currentBuild.currentResult',
    'throw err'
)
foreach ($contract in $requiredContracts) {
    if (-not $pipeline.Contains($contract)) {
        throw "Pipeline contract is missing required guard: $contract"
    }
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

Write-Output 'Repository isolation and trusted-pipeline source contracts passed. Jenkins also runs behavioral policy assertions before checkout on each build.'
