[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pipelinePath = Join-Path $repositoryRoot 'casc/pipelines/repository-pilot.groovy'
$controllerDockerfilePath = Join-Path $repositoryRoot 'Dockerfile'
$composePath = Join-Path $repositoryRoot 'compose.yaml'
$jenkinsConfigPath = Join-Path $repositoryRoot 'casc/jenkins.yaml'
$jobsPath = Join-Path $repositoryRoot 'casc/jobs.groovy'
$gitIgnorePath = Join-Path $repositoryRoot '.gitignore'
$pluginsPath = Join-Path $repositoryRoot 'plugins.txt'
$agentDockerfilePath = Join-Path $repositoryRoot 'agent/Dockerfile'
$node24DockerfilePath = Join-Path $repositoryRoot 'agent/Node24.Dockerfile'
$playwrightDockerfilePath = Join-Path $repositoryRoot 'agent/Playwright.Dockerfile'
$e2ePipelinePath = Join-Path $repositoryRoot 'casc/pipelines/e2e.groovy'
$knownHostsPath = Join-Path $repositoryRoot 'agent/known_hosts'
$credentialScriptPath = Join-Path $repositoryRoot 'scripts/provision-vm-github-app.ps1'
$pilotConfigParserPath = Join-Path $repositoryRoot 'scripts/pilot-config.ps1'
$hypervPreflightPath = Join-Path $repositoryRoot 'scripts/hyperv-preflight.ps1'
$newVmScriptPath = Join-Path $repositoryRoot 'scripts/new-jenkins-vm.ps1'
$vmStartScriptPath = Join-Path $repositoryRoot 'scripts/vm/start-jenkins.sh'
$backupScriptPath = Join-Path $repositoryRoot 'scripts/vm/backup-jenkins.sh'
$restoreScriptPath = Join-Path $repositoryRoot 'scripts/vm/restore-jenkins-backup.sh'
$rollbackScriptPath = Join-Path $repositoryRoot 'scripts/rollback-jenkins-vm-forward.ps1'
$windowsControllerShimPath = Join-Path $repositoryRoot 'scripts/start-controller.ps1'

$pipeline = Get-Content -LiteralPath $pipelinePath -Raw
$controllerDockerfile = Get-Content -LiteralPath $controllerDockerfilePath -Raw
$compose = Get-Content -LiteralPath $composePath -Raw
$jenkinsConfig = Get-Content -LiteralPath $jenkinsConfigPath -Raw
$jobs = Get-Content -LiteralPath $jobsPath -Raw
$gitIgnore = Get-Content -LiteralPath $gitIgnorePath -Raw
$plugins = Get-Content -LiteralPath $pluginsPath -Raw
$agentDockerfile = Get-Content -LiteralPath $agentDockerfilePath -Raw
$node24Dockerfile = Get-Content -LiteralPath $node24DockerfilePath -Raw
$playwrightDockerfile = Get-Content -LiteralPath $playwrightDockerfilePath -Raw
$e2ePipeline = Get-Content -LiteralPath $e2ePipelinePath -Raw
$knownHosts = Get-Content -LiteralPath $knownHostsPath -Raw
$credentialScript = Get-Content -LiteralPath $credentialScriptPath -Raw
$pilotConfigParser = Get-Content -LiteralPath $pilotConfigParserPath -Raw
$hypervPreflight = Get-Content -LiteralPath $hypervPreflightPath -Raw
$newVmScript = Get-Content -LiteralPath $newVmScriptPath -Raw
$vmStartScript = Get-Content -LiteralPath $vmStartScriptPath -Raw
$backupScript = Get-Content -LiteralPath $backupScriptPath -Raw
$restoreScript = Get-Content -LiteralPath $restoreScriptPath -Raw
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
    'def tutorWebDirectory = /* JENKINS_PILOT_TUTOR_WEB_DIRECTORY */',
    "name: 'RUN_CLOUDFLARE_CANDIDATE'",
    'params.RUN_CLOUDFLARE_CANDIDATE == true',
    "'Cloudflare Candidate success for an owner-triggered manual run.'",
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
    "title: 'Required CI check: RUNNING'",
    "conclusion: 'FAILURE'",
    'name: candidateCheckName',
    "title: 'Cloudflare Candidate (blocked)'",
    'Controller could not publish the pre-checkout policy result',
    "stage('Pipeline policy self-test')",
    "stage('Execute trusted checks')",
    "catchError(buildResult: 'FAILURE', stageResult: 'FAILURE', catchInterruptions: false)",
    "label 'setness-ephemeral'",
    'git diff --name-only HEAD^1 HEAD',
    "assert classifyCandidateChanges([], candidatePathRules) == 'NOT_APPLICABLE'",
    'String classifyTutorWebChanges(List<String> changedPaths',
    "assert classifyCandidateChanges(['README.md'], candidatePathRules) == 'NOT_APPLICABLE'",
    'def directoryRules = candidatePathRules.findAll { rule -> rule.endsWith(''/'') }',
    'assert classifyCandidateChanges(["${rule}README.md"], candidatePathRules) == ''RELEVANT''',
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
    "stage('Tutor Web CI')",
    "label 'setness-node24-ephemeral'",
    "stage('Install Tutor Web dependencies')",
    "sh 'npm install --no-audit --no-fund'",
    'v24.21.0',
    "'Not applicable: no configured Cloudflare Candidate path changed.'",
    "assert shouldFailGateClosed('RELEVANT', 'NOT_RUN', 'SUCCESS')",
    'if (shouldFailGateClosed(',
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
$pendingPublisherIndex = $pipeline.IndexOf("title: 'Required CI check: RUNNING'")
$executeStageIndex = $pipeline.IndexOf("stage('Execute trusted checks')")
$agentAllocationIndex = $pipeline.IndexOf("label 'setness-ephemeral'")
$checkoutIndex = $pipeline.IndexOf('checkout scm')
$firstShellIndex = $pipeline.IndexOf('sh ''')
$authorizationStageIndex = $pipeline.IndexOf("stage('Authorize pull request')")
$selfTestStageIndex = $pipeline.IndexOf("stage('Pipeline policy self-test')")
if ($authorizationGuardIndex -lt 0 -or $headShaVerificationIndex -lt 0 -or $blockedPublisherIndex -lt 0 -or $pendingPublisherIndex -lt 0 -or
    $executeStageIndex -lt 0 -or $agentAllocationIndex -lt 0 -or $checkoutIndex -lt 0 -or
    $firstShellIndex -lt 0 -or $authorizationStageIndex -lt 0 -or $selfTestStageIndex -lt 0 -or
    $authorizationStageIndex -ge $selfTestStageIndex -or
    $headShaVerificationIndex -ge $blockedPublisherIndex -or
    $headShaVerificationIndex -ge $executeStageIndex -or
    $authorizationGuardIndex -ge $blockedPublisherIndex -or
    $pendingPublisherIndex -ge $checkoutIndex -or
    $blockedPublisherIndex -ge $executeStageIndex -or
    $executeStageIndex -ge $agentAllocationIndex -or
    $agentAllocationIndex -ge $checkoutIndex -or
    $checkoutIndex -ge $firstShellIndex) {
    throw 'Authorization and denial publication must run on the controller before agent provisioning, checkout, and repository commands.'
}
$executeCatchIndex = $pipeline.IndexOf("catchError(buildResult: 'FAILURE', stageResult: 'FAILURE', catchInterruptions: false)")
if ($executeCatchIndex -lt $executeStageIndex -or $executeCatchIndex -gt $checkoutIndex) {
    throw 'Ordinary lane failures must be recorded while allowing later independent verification lanes to run; user cancellation must still abort.'
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
    -not $jobs.Contains("sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.SSHCheckoutTrait')") -or
    -not $jobs.Contains("sshCheckout.appendNode('credentialsId', checkoutCredentialId)") -or
    -not $jobs.Contains("trustedAuthorsMarker = '/* JENKINS_PILOT_TRUSTED_PR_AUTHORS */'") -or
    -not $jobs.Contains('JsonOutput.toJson([targetOwner])') -or
    -not $jobs.Contains('JENKINS_GITHUB_APP_CREDENTIAL_ID') -or
    -not $jobs.Contains('JENKINS_PRIMARY_CHECK_NAME') -or
    -not $jobs.Contains('JENKINS_CANDIDATE_CHECK_NAME') -or
    -not $jobs.Contains('JENKINS_APP_DIRECTORY') -or
    -not $jobs.Contains('JENKINS_TUTOR_WEB_DIRECTORY') -or
    -not $jobs.Contains('JENKINS_E2E_JOB_NAME') -or
    -not $jobs.Contains('JENKINS_SITE_URL')) {
    throw 'The trusted PR author allowlist, repo-scoped GitHub App, private check contexts, and target paths must come from local controller configuration.'
}
if (-not $pilotConfigParser.Contains("'JENKINS_GITHUB_APP_CREDENTIAL_ID'") -or
    -not $pilotConfigParser.Contains("'github-app'") -or
    -not $pilotConfigParser.Contains('AppCredentialId = $appCredentialId') -or
    -not $pilotConfigParser.Contains("'JENKINS_CHECKOUT_SSH_CREDENTIAL_ID'") -or
    -not $pilotConfigParser.Contains("'JENKINS_TUTOR_WEB_DIRECTORY'") -or
    -not $pilotConfigParser.Contains("'JENKINS_E2E_JOB_NAME'") -or
    -not $pilotConfigParser.Contains('CheckoutCredentialId = $checkoutCredentialId') -or
    -not $pilotConfigParser.Contains('$checkoutCredentialId -eq $appCredentialId') -or
    -not $credentialScript.Contains('$appCredentialId = $pilotConfig.AppCredentialId') -or
    -not $credentialScript.Contains('$checkoutCredentialId = $pilotConfig.CheckoutCredentialId') -or
    -not $credentialScript.Contains('$encryptedCheckoutKeyPath') -or
    -not $credentialScript.Contains('BasicSSHUserPrivateKey') -or
    -not $credentialScript.Contains('PILOT_VM_GITHUB_APP_AND_READ_ONLY_CHECKOUT_CONFIGURED') -or
    $credentialScript -match '\$appCredentialId\s*=\s*["'']' -or
    $credentialScript -match '\$checkoutCredentialId\s*=\s*["'']') {
    throw 'The VM provisioner must use separate, validated local App and read-only checkout credentials rather than embedding private identifiers.'
}
if (-not $credentialScript.Contains('Controller-only GitHub App for discovery and Checks') -or
    -not $credentialScript.Contains('Repository-scoped read-only checkout deploy key')) {
    throw 'The App and SSH checkout credentials must remain separate and be provisioned as distinct credential types.'
}
if (-not $jobs.Contains("sourceTraits.appendNode('io.jenkins.plugins.checks.github.status.GitHubSCMSourceStatusChecksTrait')") -or
    -not $jobs.Contains("gateChecks.appendNode('skip', 'true')") -or
    -not $jobs.Contains("gateChecks.appendNode('skipNotifications', 'true')")) {
    throw 'The trusted Pipeline must own readable primary-check output while leaving parse failures pending and fail-closed.'
}
if (-not $gitIgnore.Contains('*.env')) {
    throw 'Local environment files must be ignored by Git.'
}

if (-not $compose.Contains('${JENKINS_HTTP_BIND_IP:-127.0.0.1}:${JENKINS_HTTP_PORT:-18080}:8080')) {
    throw 'Jenkins must default to loopback and support binding only to the VM host-only address.'
}
foreach ($privateConfigurationKey in @('JENKINS_GITHUB_APP_CREDENTIAL_ID', 'JENKINS_CHECKOUT_SSH_CREDENTIAL_ID', 'JENKINS_PRIMARY_CHECK_NAME', 'JENKINS_CANDIDATE_CHECK_NAME', 'JENKINS_APP_DIRECTORY', 'JENKINS_TUTOR_WEB_DIRECTORY', 'JENKINS_E2E_JOB_NAME', 'JENKINS_SITE_URL')) {
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
foreach ($agentContract in @(
    'labelString: "setness-node24-ephemeral"',
    'image: "jenkins-pilot-agent:node-24.21.0"',
    'labelString: "setness-e2e-ephemeral"',
    'image: "jenkins-pilot-agent:node-22.23.3-playwright-1.62.1"'
)) {
    if (-not $jenkinsConfig.Contains($agentContract)) {
        throw "A required one-use verification agent is missing: $agentContract."
    }
}
if (-not $plugins.Contains('docker-plugin:1327.v9524f1ee134e')) {
    throw 'The Docker cloud plugin must be explicitly version-pinned.'
}
if (-not $agentDockerfile.Contains('openssh-client') -or
    -not $agentDockerfile.Contains('agent/known_hosts') -or
    -not $knownHosts.Contains('github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl')) {
    throw 'The SSH checkout agent must include the pinned GitHub host key and SSH client.'
}
if (-not $agentDockerfile.Contains('v22.23.3') -or
    -not $node24Dockerfile.Contains('v24.21.0') -or
    -not $node24Dockerfile.Contains('sha256sum --check --strict') -or
    -not $playwrightDockerfile.Contains('PLAYWRIGHT_VERSION=1.62.1') -or
    -not $playwrightDockerfile.Contains('playwright install-deps chromium') -or
    -not $playwrightDockerfile.Contains('playwright install chromium') -or
    -not $playwrightDockerfile.Contains('USER jenkins')) {
    throw 'The pinned Node 22, Node 24, and pre-baked unprivileged Playwright agent images are incomplete.'
}
if (-not $compose.Contains('dockerfile: agent/Node24.Dockerfile') -or
    -not $compose.Contains('dockerfile: agent/Playwright.Dockerfile') -or
    -not $compose.Contains('jenkins-pilot-agent:node-24.21.0') -or
    -not $compose.Contains('jenkins-pilot-agent:node-22.23.3-playwright-1.62.1')) {
    throw 'Compose must define buildable, pinned Node 24 and Playwright image profiles.'
}
if (-not $e2ePipeline.Contains('TARGET_SHA') -or
    -not $e2ePipeline.Contains("name: 'jenkins-e2e'") -or
    -not $e2ePipeline.Contains('JENKINS_E2E_CHECKED_OUT_SHA = checkedOutSha') -or
    -not $e2ePipeline.Contains('https://api.github.com/repos/${owner}/${repository}/check-runs') -or
    -not $e2ePipeline.Contains(".header('Authorization',") -or
    -not $e2ePipeline.Contains('Bearer ${token}') -or
    -not $e2ePipeline.Contains("head_sha: headSha.toLowerCase()") -or
    -not $e2ePipeline.Contains("status: 'in_progress'") -or
    -not $e2ePipeline.Contains("status: 'completed'") -or
    -not $e2ePipeline.Contains("conclusion: conclusion") -or
    -not $e2ePipeline.Contains('CredentialsProvider.findCredentialById') -or
    -not $e2ePipeline.Contains('GitHubAppCredentials.class') -or
    -not $e2ePipeline.Contains('java.net.http.HttpClient') -or
    -not $e2ePipeline.Contains('.method(method,') -or
    -not $e2ePipeline.Contains('connectTimeout(java.time.Duration.ofSeconds(10))') -or
    -not $e2ePipeline.Contains("timeout(java.time.Duration.ofSeconds(20))") -or
    -not $e2ePipeline.Contains('response.app?.id?.toString() != appId') -or
    -not $e2ePipeline.Contains('response.head_sha?.toString()?.equalsIgnoreCase(headSha) != true') -or
    $e2ePipeline.Contains('publishChecks(') -or
    $e2ePipeline.Contains('HttpURLConnection') -or
    -not $e2ePipeline.Contains('test:e2e:finance-gpt-fail-closed') -or
    -not $e2ePipeline.Contains('e2e/ai-skills-pack.spec.ts') -or
    -not $e2ePipeline.Contains('test "$(node --version)" = "v22.23.3"') -or
    -not $e2ePipeline.Contains('test "$(npx playwright --version)" = "Version 1.62.1"') -or
    -not $e2ePipeline.Contains('finally') -or
    -not $e2ePipeline.Contains('deleteDir()')) {
    throw 'The separate centrally trusted E2E job must retain its daily UTC schedule, exact-SHA guard, pinned toolchain, full test set, and cleanup.'
}
if ($e2ePipeline -match '(?im)^\s*(?:echo|println)\s+.*(?:installationToken|privateKey|credential\.getPassword)') {
    throw 'The controller-side E2E publisher must never log GitHub App credential material.'
}
if (-not $controllerDockerfile.Contains('jdk21')) {
    throw 'The explicit E2E Checks API publisher requires the pinned Java 21 controller runtime.'
}
if (-not $jobs.Contains("cron('37 6 * * *')") -or
    -not $jobs.Contains('pipelineJob(e2eJobName)') -or
    -not $jobs.Contains('script(e2ePipelineTemplate)') -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_REPOSITORY */'") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_DETAILS_BASE */'") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_APP_CREDENTIAL_ID */'") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_APP_ID */'") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_REPOSITORY_OWNER */'") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_REPOSITORY_NAME */'")) {
    throw 'CasC must install the independent scheduled/manual E2E job from the checked-in trusted Pipeline.'
}
if ($agentDockerfile.Contains('JENKINS_SECRET') -or $agentDockerfile.Contains('GITHUB_APP')) {
    throw 'The one-use agent image must not contain App keys or persistent-agent secrets.'
}
if (-not $credentialScript.Contains('DefaultPermissionsStrategy.CONTENTS_READ') -or
    $credentialScript.Contains('DefaultPermissionsStrategy.INHERIT_ALL')) {
    throw 'The repository-discovery App must retain its least-privilege default for untrusted contexts; checkout must use the separate SSH credential.'
}
if (-not $hypervPreflight.Contains("KeyProtectorType -eq 'RecoveryPassword'") -or
    -not $hypervPreflight.Contains('Hyper-V is not enabled; enable it and reboot only after reviewing these preflight results.') -or
    -not $hypervPreflight.Contains('Get-BitLockerVolume -MountPoint $ProtectedVolume') -or
    -not $hypervPreflight.Contains("throw 'Host prerequisites are not yet ready. No VM, network, firewall, or credential state was changed.'") -or
    -not $newVmScript.Contains('RECOVERY-KEY-VERIFIED') -or
    -not $newVmScript.Contains('[string] $RecoveryKeyConfirmation')) {
    throw 'VM creation must require a BitLocker recovery-password protector and explicit operator confirmation that recovery material is retrievable.'
}
if (-not $vmStartScript.Contains('[[ "$action" == start || "$action" == install || "$action" == restart ]]') -or
    -not $vmStartScript.Contains('export JENKINS_ADMIN_PASSWORD="$(<"$admin_password_file")"')) {
    throw 'Every controller-starting action, including first install, must load the protected bootstrap password rather than a placeholder.'
}
if (-not $vmStartScript.Contains('build controller agent-image node24-agent-image e2e-agent-image')) {
    throw 'VM installation and restart must prebuild every disposable agent profile.'
}
foreach ($agentImage in @(
    'jenkins-pilot-agent:node-22.23.3',
    'jenkins-pilot-agent:node-24.21.0',
    'jenkins-pilot-agent:node-22.23.3-playwright-1.62.1'
)) {
    if (-not $backupScript.Contains($agentImage) -or -not $restoreScript.Contains($agentImage)) {
        throw "Backup and restore safety checks must account for every disposable agent image: $agentImage."
    }
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
$candidateGuardIndex = $pipeline.IndexOf("if (env.JENKINS_CLOUDFLARE_CANDIDATE == 'RELEVANT')")
if ($candidateStageIndex -lt 0 -or $candidateGuardIndex -lt 0 -or $candidateStageIndex -lt $candidateGuardIndex) {
    throw 'Cloudflare Candidate commands must require either relevant paths or an explicit owner-triggered manual request.'
}
if ($pipeline.Contains("if (isPullRequest && env.JENKINS_CLOUDFLARE_CANDIDATE == 'RELEVANT')") -or
    -not $pipeline.Contains('candidatePaths.isEmpty() && !manualCandidateRequested')) {
    throw 'Candidate runs must support the manual workflow_dispatch equivalent without making Candidate unconditional.'
}
if (-not $pipeline.Contains("withEnv(['CLOUDFLARE_ENV=staging'])") -or
    $pipeline.Contains("sh 'CLOUDFLARE_ENV=staging npm run cloudflare:validate'")) {
    throw 'Every Candidate validation command must run in the staging environment, without provider credentials or deployment capability.'
}

Write-Output 'Compose isolation, disposable Node 22/Node 24/Playwright agents, controller-before-checkout authorization, separate verification lanes, credential boundaries, check reporting, recovery gates, and trusted-pipeline contracts passed.'
