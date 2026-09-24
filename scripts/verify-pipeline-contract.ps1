[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pipelinePath = Join-Path $repositoryRoot 'casc/pipelines/repository-pilot.groovy'
$composePath = Join-Path $repositoryRoot 'compose.yaml'
$jenkinsConfigPath = Join-Path $repositoryRoot 'casc/jenkins.yaml'
$jobsPath = Join-Path $repositoryRoot 'casc/jobs.groovy'
$gitIgnorePath = Join-Path $repositoryRoot '.gitignore'
$pluginsPath = Join-Path $repositoryRoot 'plugins.txt'
$agentDockerfilePath = Join-Path $repositoryRoot 'agent/Dockerfile'
$credentialScriptPath = Join-Path $repositoryRoot 'scripts/provision-vm-github-app.ps1'
$pilotConfigParserPath = Join-Path $repositoryRoot 'scripts/pilot-config.ps1'
$vmStartScriptPath = Join-Path $repositoryRoot 'scripts/vm/start-jenkins.sh'
$rollbackScriptPath = Join-Path $repositoryRoot 'scripts/rollback-jenkins-vm-forward.ps1'
$windowsControllerShimPath = Join-Path $repositoryRoot 'scripts/start-controller.ps1'

$pipeline = Get-Content -LiteralPath $pipelinePath -Raw
$compose = Get-Content -LiteralPath $composePath -Raw
$jenkinsConfig = Get-Content -LiteralPath $jenkinsConfigPath -Raw
$jobs = Get-Content -LiteralPath $jobsPath -Raw
$gitIgnore = Get-Content -LiteralPath $gitIgnorePath -Raw
$plugins = Get-Content -LiteralPath $pluginsPath -Raw
$agentDockerfile = Get-Content -LiteralPath $agentDockerfilePath -Raw
$credentialScript = Get-Content -LiteralPath $credentialScriptPath -Raw
$pilotConfigParser = Get-Content -LiteralPath $pilotConfigParserPath -Raw
$vmStartScript = Get-Content -LiteralPath $vmStartScriptPath -Raw
$windowsControllerShim = Get-Content -LiteralPath $windowsControllerShimPath -Raw

$environmentBlockFound = $false
$insideEnvironmentBlock = $false
foreach ($line in (Get-Content -LiteralPath $pipelinePath)) {
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
    'def primaryCheckName = /* JENKINS_PILOT_PRIMARY_CHECK_NAME */',
    'def candidateCheckName = /* JENKINS_PILOT_CANDIDATE_CHECK_NAME */',
    'def appDirectory = /* JENKINS_PILOT_APP_DIRECTORY */',
    'String verifiedPullRequestHeadSha(def run, String expectedChangeId)',
    'agent none',
    "stage('Authorize pull request')",
    "isAuthorizedPullRequestAuthor(env.CHANGE_AUTHOR, trustedPullRequestAuthors)",
    'verifiedPullRequestHeadSha(currentBuild.rawBuild, changeId)',
    'jenkins.scm.api.SCMRevisionAction.class',
    'org.jenkinsci.plugins.github_branch_source.PullRequestSCMRevision',
    'pullRequestHead.getId() != expectedChangeId',
    "System.getenv('JENKINS_TARGET_REPO_OWNER')",
    "System.getenv('JENKINS_TARGET_REPO_NAME')",
    'pullRequestHead.getSourceOwner()',
    'pullRequestHead.getSourceRepo()',
    'revision.getPullHash()',
    'Verified PR head SHA:',
    'if (!(verifiedHeadSha ==~ /(?i)[0-9a-f]{40}|[0-9a-f]{64}/))',
    'no GitHub checks were published and no repository code was run.',
    'Owner-only Jenkins shadow: PR author is not allowlisted',
    'name: primaryCheckName',
    "title: 'Required CI check: BLOCKED'",
    "conclusion: 'FAILURE'",
    'name: candidateCheckName',
    "title: 'Cloudflare Candidate (blocked)'",
    'Controller could not publish the pre-checkout policy result',
    "stage('Pipeline policy self-test')",
    "stage('Execute trusted checks')",
    "label 'setness-ephemeral'",
    'git diff --name-only HEAD^1 HEAD',
    "assert classifyCandidateChanges([], candidatePathRules) == 'NOT_APPLICABLE'",
    "if (path.toLowerCase().endsWith('.md'))",
    'def directoryRules = candidatePathRules.findAll { rule -> rule.endsWith(''/'') }',
    'pilot-example.mdx',
    'README.md',
    "assert isAuthorizedPullRequestAuthor(trustedPullRequestAuthors[0], trustedPullRequestAuthors)",
    "assert !isAuthorizedPullRequestAuthor('untrusted-contributor', trustedPullRequestAuthors)",
    "assert !isAuthorizedPullRequestAuthor(null, trustedPullRequestAuthors)",
    "assert candidateCheckConclusion('BLOCKED', 'NOT_RUN') == 'NEUTRAL'",
    "assert candidateCheckConclusion('UNCLASSIFIED', 'NOT_RUN') == 'FAILURE'",
    "assert candidateCheckConclusion('RELEVANT', 'CANCELED') == 'CANCELED'",
    "assert candidateCheckSummary('DENIED', 'BLOCKED', 'NOT_RUN', '0').startsWith('Not run: owner-only policy')",
    "stage('Node 22 runtime')",
    "stage('Install dependencies (npm ci)')",
    "stage('Typecheck')",
    "stage('Lint')",
    "stage('Build')",
    "stage('Blog validation')",
    "stage('SEO baseline')",
    "stage('Tests')",
    "stage('MDX validation')",
    "stage('Vinext check')",
    "stage('Vinext staging build')",
    "stage('Cloudflare configuration validation')",
    "stage('Wrangler validation')",
    "stage('Wrangler dry-run deploy')",
    "stage('Reviewer result summary')",
    "'Not applicable: no configured Cloudflare Candidate path changed.'",
    "assert shouldFailGateClosed('RELEVANT', 'NOT_RUN', 'SUCCESS')",
    "if (shouldFailGateClosed(candidateState, candidateRunResult, currentBuild.currentResult))",
    "currentBuild.result = 'FAILURE'",
    'summary: gateSummary',
    'text: gateText',
    'deleteDir()',
    'checkout scm'
)
foreach ($contract in $requiredContracts) {
    if (-not $pipeline.Contains($contract)) {
        throw "Pipeline contract is missing required guard: $contract"
    }
}

$authorizationGuardIndex = $pipeline.IndexOf('isAuthorizedPullRequestAuthor(env.CHANGE_AUTHOR')
$headShaVerificationIndex = $pipeline.IndexOf('verifiedPullRequestHeadSha(currentBuild.rawBuild, changeId)')
$blockedPublisherIndex = $pipeline.IndexOf("title: 'Required CI check: BLOCKED'")
$executeStageIndex = $pipeline.IndexOf("stage('Execute trusted checks')")
$agentAllocationIndex = $pipeline.IndexOf("label 'setness-ephemeral'")
$checkoutIndex = $pipeline.IndexOf('checkout scm')
$firstShellIndex = $pipeline.IndexOf('sh ''')
$authorizationStageIndex = $pipeline.IndexOf("stage('Authorize pull request')")
$selfTestStageIndex = $pipeline.IndexOf("stage('Pipeline policy self-test')")
if ($authorizationGuardIndex -lt 0 -or $headShaVerificationIndex -lt 0 -or $blockedPublisherIndex -lt 0 -or
    $executeStageIndex -lt 0 -or $agentAllocationIndex -lt 0 -or $checkoutIndex -lt 0 -or
    $firstShellIndex -lt 0 -or $authorizationStageIndex -lt 0 -or $selfTestStageIndex -lt 0 -or
    $authorizationStageIndex -ge $selfTestStageIndex -or
    $headShaVerificationIndex -ge $blockedPublisherIndex -or
    $headShaVerificationIndex -ge $executeStageIndex -or
    $authorizationGuardIndex -ge $blockedPublisherIndex -or
    $blockedPublisherIndex -ge $executeStageIndex -or
    $executeStageIndex -ge $agentAllocationIndex -or
    $agentAllocationIndex -ge $checkoutIndex -or
    $checkoutIndex -ge $firstShellIndex) {
    throw 'Authorization and denial publication must run on the controller before agent provisioning, checkout, and repository commands.'
}
$postBlockIndex = $pipeline.IndexOf('    post {')
if ($postBlockIndex -lt 0) {
    throw 'Could not find the post-build check publisher block.'
}
$postHeadShaGuardIndex = $pipeline.IndexOf('if (!(verifiedHeadSha ==~ /(?i)[0-9a-f]{40}|[0-9a-f]{64}/))', $postBlockIndex)
$postCandidatePublisherIndex = $pipeline.IndexOf('name: candidateCheckName', $postBlockIndex)
$postGatePublisherIndex = $pipeline.IndexOf('name: primaryCheckName', $postBlockIndex)
if ($postHeadShaGuardIndex -lt $postBlockIndex -or
    $postCandidatePublisherIndex -lt $postHeadShaGuardIndex -or
    $postGatePublisherIndex -lt $postHeadShaGuardIndex) {
    throw 'The post-build publisher must refuse every check publication unless the controller-verified PR head SHA is valid.'
}
if (-not $jobs.Contains('scanCredentialsId(appCredentialId)') -or
    -not $jobs.Contains("trustedAuthorsMarker = '/* JENKINS_PILOT_TRUSTED_PR_AUTHORS */'") -or
    -not $jobs.Contains('JsonOutput.toJson([targetOwner])') -or
    -not $jobs.Contains('JENKINS_GITHUB_APP_CREDENTIAL_ID') -or
    -not $jobs.Contains('JENKINS_PRIMARY_CHECK_NAME') -or
    -not $jobs.Contains('JENKINS_CANDIDATE_CHECK_NAME') -or
    -not $jobs.Contains('JENKINS_APP_DIRECTORY') -or
    -not $jobs.Contains('JENKINS_SITE_URL')) {
    throw 'The trusted PR author allowlist, repo-scoped GitHub App, private check contexts, and target paths must come from local controller configuration.'
}
if (-not $pilotConfigParser.Contains("'JENKINS_GITHUB_APP_CREDENTIAL_ID'") -or
    -not $pilotConfigParser.Contains("'github-app'") -or
    -not $pilotConfigParser.Contains('AppCredentialId = $appCredentialId') -or
    -not $credentialScript.Contains('$appCredentialId = $pilotConfig.AppCredentialId') -or
    $credentialScript -match '\$appCredentialId\s*=\s*["'']') {
    throw 'The VM provisioner must consume a validated, ignored local App credential ID rather than embedding a private identifier.'
}
if ($jobs.Contains('SSHCheckoutTrait') -or $jobs.Contains('setness-jenkins-readonly-checkout')) {
    throw 'App-based checkout must replace the persistent SSH deploy key in the new controller configuration.'
}
if (-not $jobs.Contains("sourceTraits.appendNode('io.jenkins.plugins.checks.github.status.GitHubSCMSourceStatusChecksTrait')") -or
    -not $jobs.Contains("gateChecks.appendNode('skip', 'false')") -or
    -not $jobs.Contains("gateChecks.appendNode('skipNotifications', 'true')")) {
    throw 'The primary GitHub Checks lifecycle publisher must remain enabled without legacy Status API notifications.'
}
if (-not $gitIgnore.Contains('*.env')) {
    throw 'Local environment files must be ignored by Git.'
}

if (-not $compose.Contains('${JENKINS_HTTP_BIND_IP:-127.0.0.1}:${JENKINS_HTTP_PORT:-18080}:8080')) {
    throw 'Jenkins must default to loopback and support binding only to the VM host-only address.'
}
foreach ($privateConfigurationKey in @('JENKINS_GITHUB_APP_CREDENTIAL_ID', 'JENKINS_PRIMARY_CHECK_NAME', 'JENKINS_CANDIDATE_CHECK_NAME', 'JENKINS_APP_DIRECTORY', 'JENKINS_SITE_URL')) {
    if (-not $compose.Contains($privateConfigurationKey)) {
        throw "Private target configuration must be injected from local runtime settings: $privateConfigurationKey."
    }
}
if (-not $jenkinsConfig.Contains('numExecutors: 0')) {
    throw 'The Jenkins controller must have zero build executors.'
}
$controllerSectionMatch = [regex]::Match($compose, '(?ms)^  controller:\r?\n(?<body>.*?)(?=^  agent-image:)')
$agentImageSectionMatch = [regex]::Match($compose, '(?ms)^  agent-image:\r?\n(?<body>.*?)(?=^  [A-Za-z0-9_-]+:\s*$|^volumes:\s*$)')
if (-not $controllerSectionMatch.Success -or -not $agentImageSectionMatch.Success) {
    throw 'Could not locate the controller and build-agent image Compose services.'
}
$controllerSection = $controllerSectionMatch.Groups['body'].Value
$agentImageSection = $agentImageSectionMatch.Groups['body'].Value
if (-not $controllerSection.Contains('/var/run/docker.sock:/var/run/docker.sock') -or
    [regex]::Matches($compose, '/var/run/docker.sock').Count -ne 2) {
    throw 'Only the controller may mount the VM Docker socket and use the Docker cloud.'
}
if ($agentImageSection -match '(?m)^    volumes:\s*$' -or
    $agentImageSection.Contains('jenkins_home') -or
    $agentImageSection.Contains('docker.sock') -or
    $agentImageSection.Contains('JENKINS_SECRET')) {
    throw 'The ephemeral build image must not receive host/controller mounts or a persistent agent secret.'
}
$restoreSectionMatch = [regex]::Match($compose, '(?ms)^  restore-check:\r?\n(?<body>.*?)(?=^volumes:\s*$)')
if (-not $restoreSectionMatch.Success) {
    throw 'The network-isolated backup restore-check service is missing.'
}
$restoreSection = $restoreSectionMatch.Groups['body'].Value
if (-not $restoreSection.Contains('network_mode: none') -or
    $restoreSection.Contains('/var/run/docker.sock') -or
    $restoreSection.Contains('setness-jenkins-private') -or
    $restoreSection -match '(?m)^    ports:\s*$') {
    throw 'The restore rehearsal controller must have no network, published port, or Docker socket.'
}
if (-not $compose.Contains('name: ${JENKINS_HOME_VOLUME:-setness-jenkins-vm-home}')) {
    throw 'The restore drill must be able to mount a distinct named volume without changing the active Jenkins home.'
}
if (-not $windowsControllerShim.Contains('Hyper-V-only') -or $windowsControllerShim.Contains('docker compose')) {
    throw 'The Windows launcher must fail closed instead of starting the VM-authoritative controller on Docker Desktop.'
}
foreach ($legacyScript in @('enroll-agent.ps1', 'add-readonly-deploy-key.ps1', 'provision-github-credentials.ps1', 'show-admin-password.ps1')) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot $legacyScript)) {
        throw "The legacy persistent-agent credential path must not remain in the Hyper-V rollout: $legacyScript."
    }
}
if (-not (Test-Path -LiteralPath $rollbackScriptPath -PathType Leaf)) {
    throw 'The exact loopback forward rollback script is missing.'
}
if (-not $jenkinsConfig.Contains('containerCap: 1') -or
    -not $jenkinsConfig.Contains('instanceCap: 1') -or
    -not $jenkinsConfig.Contains('$class: com.nirima.jenkins.plugins.docker.strategy.DockerOnceRetentionStrategy') -or
    -not $jenkinsConfig.Contains('idleMinutes: 0') -or
    -not $jenkinsConfig.Contains('labelString: "setness-ephemeral"') -or
    -not $jenkinsConfig.Contains('removeVolumes: true') -or
    -not $jenkinsConfig.Contains('memoryLimit: 8192') -or
    -not $jenkinsConfig.Contains('memorySwap: 8192') -or
    -not $jenkinsConfig.Contains('cpus: "4.0"') -or
    -not $jenkinsConfig.Contains('privileged: false') -or
    -not $jenkinsConfig.Contains('network: "setness-jenkins-private"')) {
    throw 'The Docker cloud must provision a single resource-limited, unprivileged, one-build agent on its private network.'
}
if ($jenkinsConfig.Contains('permanent:') -or $jenkinsConfig.Contains('setness-linux-agent')) {
    throw 'A persistent Jenkins agent must not be configured.'
}
if (-not $plugins.Contains('docker-plugin:1327.v9524f1ee134e')) {
    throw 'The Docker cloud plugin must be explicitly version-pinned.'
}
if ($agentDockerfile.Contains('openssh-client') -or $agentDockerfile.Contains('known_hosts') -or
    $agentDockerfile.Contains('JENKINS_SECRET') -or $agentDockerfile.Contains('GITHUB_APP')) {
    throw 'The one-use agent image must not contain checkout keys, App keys, or agent secrets.'
}
if (-not $credentialScript.Contains('DefaultPermissionsStrategy.CONTENTS_READ') -or
    $credentialScript.Contains('DefaultPermissionsStrategy.INHERIT_ALL')) {
    throw 'Untrusted GitHub App use must be limited to repository Contents read.'
}
if (-not $vmStartScript.Contains('[[ "$action" == start || "$action" == install || "$action" == restart ]]') -or
    -not $vmStartScript.Contains('export JENKINS_ADMIN_PASSWORD="$(<"$admin_password_file")"')) {
    throw 'Every controller-starting action, including first install, must load the protected bootstrap password rather than a placeholder.'
}
if (-not $jobs.Contains('InlineDefinitionBranchProjectFactory') -or
    -not $jobs.Contains("inlineFactory.appendNode('script', trustedPipeline)") -or
    -not $jobs.Contains("inlineFactory.appendNode('sandbox', 'false')") -or
    $jobs.Contains("inlineFactory.appendNode('sandbox', 'true')")) {
    throw 'The job must execute the checked-in trusted Pipeline, not a Jenkinsfile from the target PR.'
}
if ([regex]::Matches($pipeline, "(?m)^\s*sh 'npm ci'\s*$").Count -ne 1) {
    throw 'The trusted pipeline must install Node dependencies only once per build.'
}

$candidateStageIndex = $pipeline.IndexOf("stage('Cloudflare Candidate')")
$candidateGuardIndex = $pipeline.IndexOf("if (isPullRequest && env.JENKINS_CLOUDFLARE_CANDIDATE == 'RELEVANT')")
if ($candidateStageIndex -lt 0 -or $candidateGuardIndex -lt 0 -or $candidateStageIndex -lt $candidateGuardIndex) {
    throw 'Cloudflare Candidate commands must remain restricted to relevant pull requests.'
}
if (-not $pipeline.Contains("withEnv(['CLOUDFLARE_ENV=staging'])") -or
    $pipeline.Contains("sh 'CLOUDFLARE_ENV=staging npm run cloudflare:validate'")) {
    throw 'Every Candidate validation command must run in the staging environment, without provider credentials or deployment capability.'
}

Write-Output 'Compose isolation, one-use agent limits, controller-before-checkout authorization, App permission scope, check reporting, and trusted-pipeline contracts passed.'
