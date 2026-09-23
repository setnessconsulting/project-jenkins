[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pipelinePath = Join-Path $repositoryRoot 'casc/pipelines/repository-pilot.groovy'
$pipeline = Get-Content -LiteralPath $pipelinePath -Raw
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

Write-Output 'Pipeline source contract passed. Jenkins also runs behavioral policy assertions before checkout on each build.'
