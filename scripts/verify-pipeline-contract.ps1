[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workflowPath = Join-Path $repositoryRoot '.github/workflows/ci.yml'
$pipelinePath = Join-Path $repositoryRoot 'casc/pipelines/repository-pilot.groovy'
$controllerDockerfilePath = Join-Path $repositoryRoot 'Dockerfile'
$composePath = Join-Path $repositoryRoot 'compose.yaml'
$jenkinsConfigPath = Join-Path $repositoryRoot 'casc/jenkins.yaml'
$jobsPath = Join-Path $repositoryRoot 'casc/jobs.groovy'
$environmentExamplePath = Join-Path $repositoryRoot '.env.example'
$gitIgnorePath = Join-Path $repositoryRoot '.gitignore'
$pluginsPath = Join-Path $repositoryRoot 'plugins.txt'
$agentDockerfilePath = Join-Path $repositoryRoot 'agent/Dockerfile'
$node24DockerfilePath = Join-Path $repositoryRoot 'agent/Node24.Dockerfile'
$playwrightDockerfilePath = Join-Path $repositoryRoot 'agent/Playwright.Dockerfile'
$secondaryPlaywrightDockerfilePath = Join-Path $repositoryRoot 'agent/Node24Playwright.Dockerfile'
$secondaryPipelinePath = Join-Path $repositoryRoot 'casc/pipelines/secondary-repository.groovy'
$e2ePipelinePath = Join-Path $repositoryRoot 'casc/pipelines/e2e.groovy'
$knownHostsPath = Join-Path $repositoryRoot 'agent/known_hosts'
$credentialScriptPath = Join-Path $repositoryRoot 'scripts/provision-vm-github-app.ps1'
$pilotConfigParserPath = Join-Path $repositoryRoot 'scripts/pilot-config.ps1'
$hypervPreflightPath = Join-Path $repositoryRoot 'scripts/hyperv-preflight.ps1'
$windowsLicensePolicyPath = Join-Path $repositoryRoot 'scripts/windows-license-policy.ps1'
$newVmScriptPath = Join-Path $repositoryRoot 'scripts/new-jenkins-vm.ps1'
$vmStartScriptPath = Join-Path $repositoryRoot 'scripts/vm/start-jenkins.sh'
$backupScriptPath = Join-Path $repositoryRoot 'scripts/vm/backup-jenkins.sh'
$restoreScriptPath = Join-Path $repositoryRoot 'scripts/vm/restore-jenkins-backup.sh'
$rollbackScriptPath = Join-Path $repositoryRoot 'scripts/rollback-jenkins-vm-forward.ps1'
$windowsControllerShimPath = Join-Path $repositoryRoot 'scripts/start-controller.ps1'
$testPlatformPipelinePath = Join-Path $repositoryRoot 'casc/pipelines/test-platform.groovy'
$testPlatformCatalogPath = Join-Path $repositoryRoot 'integration/test-platform-contract/src/approved-catalog.json'
$testPlatformAdapterPath = Join-Path $repositoryRoot 'integration/test-platform-contract/src/adapter.mjs'
$testPlatformWirePath = Join-Path $repositoryRoot 'integration/test-platform-contract/src/wire.mjs'
$testPlatformCliPath = Join-Path $repositoryRoot 'integration/test-platform-contract/src/cli.mjs'
$testPlatformPackagePath = Join-Path $repositoryRoot 'integration/test-platform-contract/package.json'
$testPlatformRequestFixturePath = Join-Path $repositoryRoot 'integration/test-platform-contract/fixtures/execution-request.json'
$portfolioConsumerPath = Join-Path $repositoryRoot 'integration/portfolio-profile-contract/src/consumer.mjs'
$portfolioCliPath = Join-Path $repositoryRoot 'integration/portfolio-profile-contract/src/resolve-pr.mjs'
$portfolioConsumerTestsPath = Join-Path $repositoryRoot 'integration/portfolio-profile-contract/test/consumer.test.mjs'
$portfolioCliTestsPath = Join-Path $repositoryRoot 'integration/portfolio-profile-contract/test/resolve-pr.test.mjs'
$portfolioConsumerPackagePath = Join-Path $repositoryRoot 'integration/portfolio-profile-contract/package.json'
$portfolioConsumerDocsPath = Join-Path $repositoryRoot 'docs/portfolio-profile-contract.md'
$portfolioAdapterDocsPath = Join-Path $repositoryRoot 'docs/portfolio-profile-controller-adapter.md'

# A Windows checkout keeps CRLF line endings. Normalize every inspected document
# so the structural contracts below hold on every platform.
function Read-NormalizedText {
    param([Parameter(Mandatory = $true)][string] $LiteralPath)
    return ((Get-Content -LiteralPath $LiteralPath -Raw) -replace "`r`n", "`n")
}

$pipeline = Get-Content -LiteralPath $pipelinePath -Raw
$workflow = Read-NormalizedText -LiteralPath $workflowPath
$controllerDockerfile = Get-Content -LiteralPath $controllerDockerfilePath -Raw
$compose = Get-Content -LiteralPath $composePath -Raw
$jenkinsConfig = Read-NormalizedText -LiteralPath $jenkinsConfigPath
$jobs = Get-Content -LiteralPath $jobsPath -Raw
$environmentExample = Get-Content -LiteralPath $environmentExamplePath -Raw
$gitIgnore = Get-Content -LiteralPath $gitIgnorePath -Raw
$plugins = Get-Content -LiteralPath $pluginsPath -Raw
$agentDockerfile = Get-Content -LiteralPath $agentDockerfilePath -Raw
$node24Dockerfile = Get-Content -LiteralPath $node24DockerfilePath -Raw
$playwrightDockerfile = Get-Content -LiteralPath $playwrightDockerfilePath -Raw
$secondaryPlaywrightDockerfile = Get-Content -LiteralPath $secondaryPlaywrightDockerfilePath -Raw
$secondaryPipeline = Get-Content -LiteralPath $secondaryPipelinePath -Raw
$e2ePipeline = Get-Content -LiteralPath $e2ePipelinePath -Raw
$knownHosts = Get-Content -LiteralPath $knownHostsPath -Raw
$credentialScript = Get-Content -LiteralPath $credentialScriptPath -Raw
$pilotConfigParser = Get-Content -LiteralPath $pilotConfigParserPath -Raw
$hypervPreflight = Get-Content -LiteralPath $hypervPreflightPath -Raw
$windowsLicensePolicy = Get-Content -LiteralPath $windowsLicensePolicyPath -Raw
$newVmScript = Get-Content -LiteralPath $newVmScriptPath -Raw
$vmStartScript = Get-Content -LiteralPath $vmStartScriptPath -Raw
$backupScript = Get-Content -LiteralPath $backupScriptPath -Raw
$restoreScript = Get-Content -LiteralPath $restoreScriptPath -Raw
$windowsControllerShim = Get-Content -LiteralPath $windowsControllerShimPath -Raw
$testPlatformPipeline = Read-NormalizedText -LiteralPath $testPlatformPipelinePath
$testPlatformCatalog = Read-NormalizedText -LiteralPath $testPlatformCatalogPath
$testPlatformAdapter = Read-NormalizedText -LiteralPath $testPlatformAdapterPath
$testPlatformWire = Read-NormalizedText -LiteralPath $testPlatformWirePath
$testPlatformCli = Read-NormalizedText -LiteralPath $testPlatformCliPath
$testPlatformPackage = Read-NormalizedText -LiteralPath $testPlatformPackagePath
$testPlatformRequestFixture = Read-NormalizedText -LiteralPath $testPlatformRequestFixturePath
$portfolioConsumer = Read-NormalizedText -LiteralPath $portfolioConsumerPath
$portfolioCli = Read-NormalizedText -LiteralPath $portfolioCliPath
$portfolioConsumerTests = Read-NormalizedText -LiteralPath $portfolioConsumerTestsPath
$portfolioCliTests = Read-NormalizedText -LiteralPath $portfolioCliTestsPath
$portfolioConsumerPackage = Read-NormalizedText -LiteralPath $portfolioConsumerPackagePath
$portfolioConsumerDocs = Read-NormalizedText -LiteralPath $portfolioConsumerDocsPath
$portfolioAdapterDocs = Read-NormalizedText -LiteralPath $portfolioAdapterDocsPath

if (-not $workflow.Contains('Set up Ruby for YAML validation') -or
    -not $workflow.Contains('ruby/setup-ruby@v1') -or
    -not $workflow.Contains("ruby-version: '3.2.3'") -or
    -not $workflow.Contains('Parse Jenkins Configuration as Code YAML') -or
    -not $workflow.Contains('YAML.parse_file("casc/jenkins.yaml")') -or
    -not $workflow.Contains('actions/checkout@v7') -or
    -not $workflow.Contains('actions/setup-java@v6')) {
    throw 'Repository CI must parse the Jenkins Configuration as Code YAML, not only inspect it as text.'
}

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
    "assert candidateCheckSummary('AUTHORIZED', 'RELEVANT', 'NOT_RUN', '2') ==",
    'Not run: standard CI did not complete before candidate checks could run; see the required CI result.',
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
foreach ($setting in @(
    'JENKINS_TEST_PLATFORM_JOB_NAME:',
    'JENKINS_TEST_PLATFORM_NODE:',
    'JENKINS_TEST_PLATFORM_ADAPTER_ROOT:',
    'JENKINS_TEST_PLATFORM_EVIDENCE_ROOT:'
)) {
    if (-not $restoreSection.Contains($setting)) {
        throw "The isolated restore controller must receive every required Test Platform setting: $setting."
    }
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
$oneBuildRetentionStrategyCount = [regex]::Matches(
    $jenkinsConfig,
    '(?m)^[ \t]+retentionStrategy:\r?\n[ \t]+idleMinutes: 0$'
).Count
$oneBuildTemplateCapCount = [regex]::Matches(
    $jenkinsConfig,
    '(?m)^[ \t]+instanceCapStr: "1"$'
).Count
if (-not $jenkinsConfig.Contains('containerCap: 1') -or
    $oneBuildTemplateCapCount -ne 4 -or
    $oneBuildRetentionStrategyCount -ne 4 -or
    $jenkinsConfig.Contains('$class: com.nirima.jenkins.plugins.docker.strategy.DockerOnceRetentionStrategy') -or
    $jenkinsConfig.Contains('dockerOnce:') -or
    -not $jenkinsConfig.Contains('idleMinutes: 0') -or
    -not $jenkinsConfig.Contains('labelString: "setness-ephemeral"') -or
    -not $jenkinsConfig.Contains('removeVolumes: true') -or
    -not $jenkinsConfig.Contains('memoryLimit: 8192') -or
    -not $jenkinsConfig.Contains('memorySwap: 8192') -or
    -not $jenkinsConfig.Contains('cpus: "4.0"') -or
    -not $jenkinsConfig.Contains('privileged: false') -or
    -not $jenkinsConfig.Contains('network: "setness-jenkins-private"')) {
    throw 'The Docker cloud must configure four correctly bounded one-build templates through the plugin CasC schema and provision resource-limited, unprivileged containers on its private network.'
}
if ($jenkinsConfig.Contains('permanent:') -or $jenkinsConfig.Contains('setness-linux-agent')) {
    throw 'A persistent Jenkins agent must not be configured.'
}
foreach ($agentContract in @(
    'labelString: "setness-node24-ephemeral"',
    'image: "jenkins-pilot-agent:node-24.21.0"',
    'labelString: "setness-e2e-ephemeral"',
    'image: "jenkins-pilot-agent:node-22.23.3-playwright-1.62.1"',
    'labelString: "secondary-node24-playwright-ephemeral"',
    'image: "jenkins-pilot-agent:node-24.21.0-playwright-1.62.1"'
)) {
    if (-not $jenkinsConfig.Contains($agentContract)) {
        throw "A required one-use verification agent is missing: $agentContract."
    }
}
if (-not [regex]::IsMatch(
    $jenkinsConfig,
    '(?m)^          - name: "secondary-node24-playwright-one-build"\r?\n            labelString: "secondary-node24-playwright-ephemeral"$'
)) {
    throw 'The secondary one-use agent label must remain nested under its Docker template in Jenkins CasC.'
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
if (-not $secondaryPlaywrightDockerfile.Contains('v24.21.0') -or
    -not $secondaryPlaywrightDockerfile.Contains('sha256sum --check --strict') -or
    -not $secondaryPlaywrightDockerfile.Contains('PLAYWRIGHT_VERSION=1.62.1') -or
    -not $secondaryPlaywrightDockerfile.Contains('playwright install-deps chromium firefox webkit') -or
    -not $secondaryPlaywrightDockerfile.Contains('playwright install chromium firefox webkit') -or
    -not $secondaryPlaywrightDockerfile.Contains('USER jenkins') -or
    $secondaryPlaywrightDockerfile.Contains('docker.sock') -or
    $secondaryPlaywrightDockerfile.Contains('JENKINS_SECRET') -or
    $secondaryPlaywrightDockerfile.Contains('GITHUB_APP')) {
    throw 'The secondary Node 24/Playwright image must pin Node and Playwright, preinstall all three browsers, and contain no controller or credential access.'
}
if (-not $compose.Contains('dockerfile: agent/Node24.Dockerfile') -or
    -not $compose.Contains('dockerfile: agent/Playwright.Dockerfile') -or
    -not $compose.Contains('dockerfile: agent/Node24Playwright.Dockerfile') -or
    -not $compose.Contains('jenkins-pilot-agent:node-24.21.0') -or
    -not $compose.Contains('jenkins-pilot-agent:node-22.23.3-playwright-1.62.1') -or
    -not $compose.Contains('jenkins-pilot-agent:node-24.21.0-playwright-1.62.1')) {
    throw 'Compose must define buildable, pinned Node 24 and both repository-specific Playwright profiles.'
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
    throw 'The separate centrally trusted E2E job must retain its exact-SHA guard, pinned toolchain, full test set, and cleanup.'
}
if ($e2ePipeline -match '(?im)^\s*(?:echo|println)\s+.*(?:installationToken|privateKey|credential\.getPassword)') {
    throw 'The controller-side E2E publisher must never log GitHub App credential material.'
}
if (-not $controllerDockerfile.Contains('jdk21')) {
    throw 'The explicit E2E Checks API publisher requires the pinned Java 21 controller runtime.'
}
if (-not $jobs.Contains("System.getenv('JENKINS_E2E_SCHEDULE_ENABLED')") -or
    -not $jobs.Contains("e2eScheduleEnabledValue in ['true', 'false']") -or
    -not $jobs.Contains("if (e2eScheduleEnabled) {") -or
    -not $jobs.Contains("cron('37 6 * * *')") -or
    -not $environmentExample.Contains('JENKINS_E2E_SCHEDULE_ENABLED=false') -or
    -not $compose.Contains('JENKINS_E2E_SCHEDULE_ENABLED: ${JENKINS_E2E_SCHEDULE_ENABLED:-false}') -or
    -not $pilotConfigParser.Contains("'JENKINS_E2E_SCHEDULE_ENABLED'") -or
    -not $pilotConfigParser.Contains("must be true or false") -or
    -not $pilotConfigParser.Contains('E2eScheduleEnabled = [bool]::Parse($e2eScheduleEnabled)') -or
    $jobs -notmatch '(?s)if \(e2eScheduleEnabled\)\s*\{\s*triggers\s*\{\s*cron\(''37 6 \* \* \*''\)\s*\}\s*\}' -or
    -not $jobs.Contains('pipelineJob(e2eJobName)') -or
    -not $jobs.Contains('script(e2ePipelineTemplate)') -or
    -not $jobs.Contains("stringParam('TARGET_SHA'") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_REPOSITORY */'") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_DETAILS_BASE */'") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_APP_CREDENTIAL_ID */'") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_APP_ID */': githubAppId") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_REPOSITORY_OWNER */': targetOwner") -or
    -not $jobs.Contains("'/* JENKINS_PILOT_E2E_REPOSITORY_NAME */': targetRepository") -or
    -not $jobs.Contains('e2ePipelineTemplate.replace(marker, JsonOutput.toJson(value))')) {
    throw 'CasC must install a manual E2E job and enable the daily UTC trigger only through the explicit opt-in setting.'
}
$scheduleGuardIndex = $jobs.IndexOf('if (e2eScheduleEnabled)')
$targetShaParameterIndex = $jobs.IndexOf("stringParam('TARGET_SHA'")
if ($scheduleGuardIndex -lt 0 -or $targetShaParameterIndex -lt 0 -or $targetShaParameterIndex -gt $scheduleGuardIndex) {
    throw 'The E2E manual TARGET_SHA parameter must remain available independently of the opt-in daily schedule.'
}
if ($jobs.Contains("'/* JENKINS_PILOT_E2E_APP_ID */': JsonOutput.toJson") -or
    $jobs.Contains("'/* JENKINS_PILOT_E2E_REPOSITORY_OWNER */': JsonOutput.toJson") -or
    $jobs.Contains("'/* JENKINS_PILOT_E2E_REPOSITORY_NAME */': JsonOutput.toJson")) {
    throw 'E2E App ID, owner, and repository markers must be JSON-encoded exactly once; pre-encoding them breaks App attribution and SHA validation.'
}
if ($agentDockerfile.Contains('JENKINS_SECRET') -or $agentDockerfile.Contains('GITHUB_APP')) {
    throw 'The one-use agent image must not contain App keys or persistent-agent secrets.'
}
if (-not $credentialScript.Contains('DefaultPermissionsStrategy.CONTENTS_READ') -or
    $credentialScript.Contains('DefaultPermissionsStrategy.INHERIT_ALL')) {
    throw 'The repository-discovery App must retain its least-privilege default for untrusted contexts; checkout must use the separate SSH credential.'
}
if (-not $hypervPreflight.Contains("KeyProtectorType -eq 'RecoveryPassword'") -or
    -not $hypervPreflight.Contains('Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop') -or
    -not $hypervPreflight.Contains('$operatingSystem.Caption -match ''^Microsoft Windows 11 Pro(?:\s|$)''') -or
    -not $hypervPreflight.Contains('$operatingSystem.OperatingSystemSKU -eq 48') -or
    -not $hypervPreflight.Contains('if (-not $isWindows11Pro)') -or
    -not $hypervPreflight.Contains('Get-CimInstance -ClassName SoftwareLicensingProduct') -or
    -not $hypervPreflight.Contains("ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND LicenseStatus=1") -or
    -not $hypervPreflight.Contains('-Property ApplicationID, LicenseStatus, LicenseFamily, Name') -or
    -not $hypervPreflight.Contains("Test-Windows11ProLicense -Products `$licensedWindowsProducts") -or
    -not $windowsLicensePolicy.Contains("`$product.LicenseFamily -ieq 'Professional'") -or
    -not $windowsLicensePolicy.Contains("`$product.Name -ieq 'Windows(R), Professional edition'") -or
    -not $windowsLicensePolicy.Contains("`$product.ApplicationID -ieq '55c92734-d682-4d71-983e-d6ec3f16059f'") -or
    -not $windowsLicensePolicy.Contains('$product.LicenseStatus -eq 1') -or
    -not $hypervPreflight.Contains('if ($windowsActivationRead -and -not $isWindowsActivated)') -or
    -not $hypervPreflight.Contains('Windows activation state could not be read.') -or
    -not $hypervPreflight.Contains('Windows is not activated.') -or
    -not $hypervPreflight.Contains('Windows edition: $windowsEdition; Windows 11 Pro installed: $isWindows11Pro; activation: $activationStatus') -or
    -not $hypervPreflight.Contains('Hyper-V is not enabled; enable it and reboot only after reviewing these preflight results.') -or
    -not $hypervPreflight.Contains('Get-BitLockerVolume -MountPoint $ProtectedVolume') -or
    -not $hypervPreflight.Contains("throw 'Host prerequisites are not yet ready. No VM, network, firewall, or credential state was changed.'") -or
    -not $newVmScript.Contains('RECOVERY-KEY-VERIFIED') -or
    -not $newVmScript.Contains('[string] $RecoveryKeyConfirmation')) {
    throw 'VM creation must require a BitLocker recovery-password protector and explicit operator confirmation that recovery material is retrievable.'
}
. $windowsLicensePolicyPath
$licensePolicyCases = @(
    [pscustomobject]@{
        Label = 'licensed Windows 11 Pro'
        Product = [pscustomobject]@{ ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f'; LicenseStatus = 1; LicenseFamily = 'Professional'; Name = 'Windows(R), Professional edition' }
        Expected = $true
    },
    [pscustomobject]@{
        Label = 'licensed Windows Home'
        Product = [pscustomobject]@{ ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f'; LicenseStatus = 1; LicenseFamily = 'Core'; Name = 'Windows(R), Core edition' }
        Expected = $false
    },
    [pscustomobject]@{
        Label = 'licensed Windows Pro for Workstations'
        Product = [pscustomobject]@{ ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f'; LicenseStatus = 1; LicenseFamily = 'ProfessionalWorkstation'; Name = 'Windows(R), ProfessionalWorkstation edition' }
        Expected = $false
    },
    [pscustomobject]@{
        Label = 'unlicensed Windows 11 Pro'
        Product = [pscustomobject]@{ ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f'; LicenseStatus = 0; LicenseFamily = 'Professional'; Name = 'Windows(R), Professional edition' }
        Expected = $false
    },
    [pscustomobject]@{
        Label = 'licensed Office product'
        Product = [pscustomobject]@{ ApplicationID = '0ff1ce15-a989-479d-af46-f275c6370663'; LicenseStatus = 1; LicenseFamily = 'Professional'; Name = 'Windows(R), Professional edition' }
        Expected = $false
    }
)
foreach ($case in $licensePolicyCases) {
    $actual = Test-Windows11ProLicense -Products @($case.Product)
    if ($actual -ne $case.Expected) {
        throw "Windows activation policy must classify '$($case.Label)' as $($case.Expected)."
    }
}
$preflightElevationGuardIndex = $hypervPreflight.IndexOf('if (-not $principal.IsInRole')
$preflightWindowsReadIndex = $hypervPreflight.IndexOf('Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop')
if ($preflightElevationGuardIndex -lt 0 -or $preflightWindowsReadIndex -le $preflightElevationGuardIndex) {
    throw 'The Windows host preflight must require Administrator elevation before reading host state.'
}
if (-not $vmStartScript.Contains('[[ "$action" == start || "$action" == install || "$action" == restart ]]') -or
    -not $vmStartScript.Contains('export JENKINS_ADMIN_PASSWORD="$(<"$admin_password_file")"')) {
    throw 'Every controller-starting action, including first install, must load the protected bootstrap password rather than a placeholder.'
}
if (-not $vmStartScript.Contains('build controller agent-image node24-agent-image e2e-agent-image secondary-agent-image')) {
    throw 'VM installation and restart must prebuild every disposable agent profile.'
}
foreach ($agentImage in @(
    'jenkins-pilot-agent:node-22.23.3',
    'jenkins-pilot-agent:node-24.21.0',
    'jenkins-pilot-agent:node-22.23.3-playwright-1.62.1',
    'jenkins-pilot-agent:node-24.21.0-playwright-1.62.1'
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
if (-not $environmentExample.Contains('JENKINS_SECONDARY_REPO_ENABLED=false') -or
    -not $compose.Contains('JENKINS_SECONDARY_REPO_ENABLED: ${JENKINS_SECONDARY_REPO_ENABLED:-false}') -or
    -not $jobs.Contains("System.getenv('JENKINS_SECONDARY_REPO_ENABLED')") -or
    -not $jobs.Contains("if (secondaryEnabled)") -or
    -not $jobs.Contains('secondary-repository.groovy') -or
    -not $jobs.Contains("inlineFactory.appendNode('script', secondaryPipelineTemplate)") -or
    -not $jobs.Contains('OriginPullRequestDiscoveryTrait') -or
    -not $jobs.Contains('secondaryCheckoutCredentialId') -or
    -not $jobs.Contains('secondaryTrustedAuthors.isEmpty()') -or
    -not $jobs.Contains('secondaryJobName in [jobName, e2eJobName, testPlatformJobName]') -or
    -not $jobs.Contains("sshCheckout.appendNode('credentialsId', secondaryCheckoutCredentialId)") -or
    -not $jobs.Contains("branchFilter.appendNode('includes', 'main PR-*')") -or
    -not $jobs.Contains("pullRequestDiscovery.appendNode('strategyId', '1')") -or
    -not $jobs.Contains('secondarySmokeCheckName == secondaryPrimaryCheckName') -or
    -not $jobs.Contains('secondaryOwner.equalsIgnoreCase(targetOwner)') -or
    -not $jobs.Contains('secondaryRepository.equalsIgnoreCase(targetRepository)') -or
    -not $pilotConfigParser.Contains("'JENKINS_SECONDARY_REPO_ENABLED'") -or
    -not $pilotConfigParser.Contains('Enabled secondary-repository configuration') -or
    -not $pilotConfigParser.Contains('$secondarySmokeCheckName -eq $secondaryPrimaryCheckName') -or
    -not $pilotConfigParser.Contains('$sameSecondaryRepository') -or
    -not $pilotConfigParser.Contains('$secondaryOwner.Equals($owner, [StringComparison]::OrdinalIgnoreCase)') -or
    -not $pilotConfigParser.Contains('$secondaryRepository.Equals($repository, [StringComparison]::OrdinalIgnoreCase)') -or
    -not $pilotConfigParser.Contains('$secondaryJobName -in @($jobName, $e2eJobName, [string] $values[''JENKINS_TEST_PLATFORM_JOB_NAME''])')) {
    throw 'The secondary repository profile must default off and require an explicit separate checkout key, owner allowlist, and centrally injected pipeline.'
}
$secondaryAuthorizationIndex = $secondaryPipeline.IndexOf("stage('Authorize pull request')")
$secondaryRevisionIndex = $secondaryPipeline.IndexOf('verifiedSecondaryPullRequestRevision(')
$secondaryAgentIndex = $secondaryPipeline.IndexOf("label 'secondary-node24-playwright-ephemeral'")
$secondarySmokeAgentIndex = $secondaryPipeline.IndexOf("label 'secondary-node24-playwright-ephemeral'", $secondaryAgentIndex + 1)
$secondarySmokeStageIndex = $secondaryPipeline.IndexOf("stage('Read-only production smoke')")
$secondaryCheckoutIndex = $secondaryPipeline.IndexOf('checkout scm')
if (-not $secondaryPipeline.Contains('agent none') -or
    -not $secondaryPipeline.Contains('PullRequestSCMRevision') -or
    -not $secondaryPipeline.Contains('revision.getBaseHash()') -or
    -not $secondaryPipeline.Contains('secondaryCheckoutMatchesPrRevision') -or
    -not $secondaryPipeline.Contains('git rev-list --parents -n 1 HEAD') -or
    -not $secondaryPipeline.Contains('Secondary profile refuses non-main branch builds before checkout or repository commands.') -or
    -not $secondaryPipeline.Contains('getSourceOwner()') -or
    -not $secondaryPipeline.Contains('getSourceRepo()') -or
    -not $secondaryPipeline.Contains("isSecondaryAuthorAllowed(env.CHANGE_AUTHOR, trustedAuthors)") -or
    -not $secondaryPipeline.Contains('Verified PR head SHA') -or
    -not $secondaryPipeline.Contains('npm run test:math-escape-preservation') -or
    -not $secondaryPipeline.Contains('npm run typecheck') -or
    -not $secondaryPipeline.Contains('npm run lint') -or
    -not $secondaryPipeline.Contains("sh 'npm run test'") -or
    -not $secondaryPipeline.Contains("sh 'npm run build'") -or
    -not $secondaryPipeline.Contains("sh 'npm run build:e2e'") -or
    -not $secondaryPipeline.Contains('test "$(node --version)" = "v24.21.0"') -or
    -not $secondaryPipeline.Contains('Version 1.62.1') -or
    -not $secondaryPipeline.Contains('tests/wave1/e2e/foundation.spec.ts') -or
    -not $secondaryPipeline.Contains('tests/wave6/e2e/noGames.spec.ts') -or
    -not $secondaryPipeline.Contains('tests/wave7/e2e/qualification.spec.ts') -or
    -not $secondaryPipeline.Contains('same-repository PR head SHA') -or
    -not $secondaryPipeline.Contains('Not configured: owner-reviewed smoke URL is absent; no live request was made.') -or
    -not $secondaryPipeline.Contains('JENKINS_SECONDARY_CI_FAILURE_STAGE') -or
    -not $secondaryPipeline.Contains('Failure stage: ${failureStage}') -or
    -not $secondaryPipeline.Contains("? failureStage : 'not applicable'") -or
    -not $secondaryPipeline.Contains("def failureStage = isPullRequest && authorization != 'AUTHORIZED'") -or
    $secondaryPipeline.Contains('${err}') -or
    -not $secondaryPipeline.Contains("label 'secondary-node24-playwright-ephemeral'") -or
    -not $secondaryPipeline.Contains("secondarySmokeConclusion('NOT_CONFIGURED') == 'NEUTRAL'") -or
    -not $secondaryPipeline.Contains("name: smokeCheckName") -or
    -not $secondaryPipeline.Contains('deleteDir()') -or
    [regex]::Matches($secondaryPipeline, "(?m)^\s*sh 'npm ci --no-audit --no-fund'\s*$").Count -ne 1 -or
    $secondaryAuthorizationIndex -lt 0 -or $secondaryRevisionIndex -lt 0 -or
    $secondaryAgentIndex -lt 0 -or $secondarySmokeAgentIndex -lt 0 -or $secondaryCheckoutIndex -lt 0 -or
    $secondaryAuthorizationIndex -ge $secondaryAgentIndex -or
    $secondaryAuthorizationIndex -ge $secondaryCheckoutIndex -or
    $secondarySmokeStageIndex -lt 0 -or $secondarySmokeAgentIndex -lt $secondarySmokeStageIndex) {
    throw 'The secondary trusted pipeline must authorize same-repository owner PRs and verify SHA before checkout, run the Node 24/Playwright contract once per clean ephemeral workspace, and report smoke as separate/not-configured rather than a passing result.'
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

# --- Test Platform consumer contract (API-390) structural checks ------------

$testPlatformRequiredGuards = @(
    'The trusted Test Platform adapter is not configured on this controller',
    'no repository code was run',
    'JENKINS_PILOT_PR_HEAD_SHA',
    'test-platform-resolution',
    'test-platform-results',
    'agent-unavailable',
    'checkout-sha-mismatch',
    'Authorize and resolve Test Platform contract',
    'git rev-parse HEAD'
)
foreach ($guard in $testPlatformRequiredGuards) {
    if (-not $testPlatformPipeline.Contains($guard)) {
        throw "The trusted Test Platform pipeline is missing a required guard: $guard"
    }
}
$testPlatformAuthIndex = $testPlatformPipeline.IndexOf('Authorize and resolve Test Platform contract')
$testPlatformCheckoutIndex = $testPlatformPipeline.IndexOf('git rev-parse HEAD')
if ($testPlatformAuthIndex -lt 0 -or $testPlatformCheckoutIndex -lt 0 -or $testPlatformAuthIndex -ge $testPlatformCheckoutIndex) {
    throw 'The Test Platform contract must be authorized on the controller before any checkout.'
}
if ($testPlatformPipeline.Contains('${plan.') -or $testPlatformPipeline.Contains('${suite.')) {
    throw 'The trusted Test Platform pipeline must not interpolate plan-controlled values.'
}

$testPlatformCatalog = $testPlatformCatalog | ConvertFrom-Json
if ($testPlatformCatalog.contract.contract_id -ne 'jenkins-execution-contract' -or
    $testPlatformCatalog.contract.contract_version -ne '1.0.0' -or
    $testPlatformCatalog.contract.plan_schema_versions -notcontains '1' -or
    $testPlatformCatalog.contract.receipt_schema_versions -notcontains '1') {
    throw 'The approved Test Platform catalog must mirror the canonical jenkins-execution-contract 1.0.0 schema versions.'
}
foreach ($limitName in @('max_suites', 'max_artifacts_per_suite', 'max_artifact_bytes', 'max_evidence_references_per_suite', 'max_diagnostics_per_outcome', 'max_diagnostic_message_length', 'max_suite_timeout_seconds', 'max_execution_seconds')) {
    if ($null -eq $testPlatformCatalog.limits.$limitName) {
        throw "The approved Test Platform catalog is missing the bounded limit: $limitName."
    }
}
foreach ($executorId in @('node-22-deterministic', 'node-24-deterministic', 'browser-e2e', 'container-infrastructure')) {
    if ($null -eq $testPlatformCatalog.executors.$executorId) {
        throw "The approved Test Platform catalog is missing the approved executor: $executorId."
    }
}
foreach ($suiteId in @('verify', 'standard', 'typecheck', 'tutor-web', 'e2e', 'qualify', 'qualify:live')) {
    if ($null -eq $testPlatformCatalog.suites.$suiteId) {
        throw "The approved Test Platform catalog is missing the approved suite: $suiteId."
    }
}

foreach ($adapterGuard in @('ContractRejection', 'verifyRequest', 'buildSubmission')) {
    if (-not $testPlatformAdapter.Contains($adapterGuard)) {
        throw "The trusted Test Platform adapter is missing required logic: $adapterGuard"
    }
}
foreach ($wireGuard in @('validateExecutionRequest', 'validateReceiptSubmission', 'validateExecutorResults')) {
    if (-not $testPlatformWire.Contains($wireGuard)) {
        throw "The trusted Test Platform consumer wire is missing required validation: $wireGuard"
    }
}
foreach ($cliGuard in @('finalize', 'verify')) {
    if (-not $testPlatformCli.Contains($cliGuard)) {
        throw "The trusted Test Platform adapter CLI is missing required subcommand: $cliGuard"
    }
}

if (-not $jobs.Contains('test-platform.groovy') -or -not $jobs.Contains('testPlatformPipelineTemplate')) {
    throw 'CasC must install the trusted Test Platform pipeline exactly like the other trusted pipelines.'
}
if (-not $controllerDockerfile.Contains('integration/test-platform-contract') -or -not $controllerDockerfile.Contains('nodejs.org')) {
    throw 'The controller image must provision the pinned Node runtime and the trusted Test Platform adapter.'
}
$controllerNodeInstallMarkers = @(
    'USER root',
    'apt-get install --yes --no-install-recommends ca-certificates curl xz-utils',
    'node-v22.23.3-linux-x64.tar.xz',
    'df450af89261115ef9f9e3830c3eeb2cc9213b63c720b1af623cb5dcbe2e02de',
    '--directory /opt/setness-jenkins/tools/node-v22.23.3-linux-x64',
    'PATH="/opt/setness-jenkins/tools/node-v22.23.3-linux-x64/bin:${PATH}"',
    'USER jenkins'
)
$controllerNodeInstallPositions = @(
    foreach ($marker in $controllerNodeInstallMarkers) {
        $controllerDockerfile.IndexOf($marker, [StringComparison]::Ordinal)
    }
)
if ($controllerNodeInstallPositions -contains -1) {
    throw 'The controller Node runtime must install xz support, verify the pinned archive, and use a Jenkins-owned tool path.'
}
for ($index = 1; $index -lt $controllerNodeInstallPositions.Count; $index++) {
    if ($controllerNodeInstallPositions[$index] -le $controllerNodeInstallPositions[$index - 1]) {
        throw 'The controller Node runtime must switch to root only for installation and return to Jenkins afterward.'
    }
}

$testPlatformFixture = $testPlatformRequestFixture | ConvertFrom-Json
if ($testPlatformFixture.contract_id -ne $testPlatformCatalog.contract.contract_id -or
    $testPlatformFixture.contract_version -ne $testPlatformCatalog.contract.contract_version) {
    throw 'The synthetic Test Platform request fixture must match the approved catalog contract identity.'
}

foreach ($portfolioGuard in @(
    'export const IMPLEMENTATIONS = Object.freeze({',
    "'node22-foundation-v1'",
    "nodeVersion: '22.23.3'",
    "'node24-lint-typescript-test-v1'",
    "agentClass: 'setness-node24-ephemeral'",
    "nodeVersion: '24.21.0'",
    'commands: Object.freeze([',
    "Object.freeze(['npm', 'run', 'check'])",
    "Object.freeze(['npm', 'test'])",
    "Object.freeze(['npm', 'run', 'lint'])",
    "Object.freeze(['node_modules/.bin/tsc', '--noEmit'])",
    'export function validateProfileCatalog(catalog)',
    'function resolveShadowExecution(catalog, profileId, headSha)',
    'export function resolveAuthorizedShadowPullRequest(',
    "execution.repository.toLowerCase() !== verified.repository.toLowerCase()",
    "profile.status !== 'shadow'",
    'profile.requiredNodeVersion !== implementation.nodeVersion',
    "reject('runtime-mismatch'",
    'profile.repositories.length !== 1',
    'implementation.requiredCheck',
    'export function verifyPullRequestHead(pr,',
    'currentHeadSha.toLowerCase() !== canonicalSha',
    'typeof headRepository !== ''string''',
    'headRepository.toLowerCase() !== expectedRepository',
    'typeof baseRepository !== ''string''',
    'baseRepository.toLowerCase() !== expectedRepository',
    "'author-not-allowed'",
    "'stale-or-untrusted-pr'"
)) {
    if (-not $portfolioConsumer.Contains($portfolioGuard)) {
        throw "The trusted portfolio profile consumer is missing a required fail-closed guard: $portfolioGuard"
    }
}
if (-not $portfolioConsumer.Contains('const PROFILE_KEYS = new Set([') -or
    $portfolioConsumer.Contains('export function resolveShadowExecution(catalog, profileId, headSha)') -or
    -not $portfolioConsumer.Contains("if (!allowed.has(key)) reject('unexpected-field'") -or
    -not $portfolioConsumerTests.Contains('rejects profile fields that could inject commands or credentials') -or
    -not $portfolioConsumerTests.Contains('accepts only exact, open, same-repository PR heads from allowlisted authors') -or
    -not $portfolioConsumerTests.Contains('returns executable commands only after PR identity and profile repository bind') -or
    -not $portfolioConsumerTests.Contains('rejects a profile whose required Node.js runtime differs from the pinned agent') -or
    -not $portfolioConsumerTests.Contains('resolves the centrally pinned Node 24 lint, type, and test implementation') -or
    -not $portfolioConsumerTests.Contains('rejects qualified and fork claims without full evidence') -or
    -not $portfolioCli.Contains('readInput()') -or
    -not $portfolioCli.Contains('MAX_REQUEST_BYTES = 1024 * 1024') -or
    -not $portfolioCli.Contains("Object.freeze(['setnessconsulting'])") -or
    -not $portfolioCli.Contains('resolveAuthorizedShadowPullRequestForRepository(') -or
    $portfolioCli -match '\bresolveAuthorizedShadowPullRequest\s*\(' -or
    $portfolioCli.Contains('child_process') -or
    $portfolioCli.Contains('process.env') -or
    -not $portfolioCliTests.Contains('controller stdin adapter emits only the centrally defined plan') -or
    -not $portfolioCliTests.Contains('rejects outside authors, stale heads, and an injected author allowlist') -or
    -not $controllerDockerfile.Contains('integration/portfolio-profile-contract /usr/share/jenkins/portfolio-profile-contract') -or
    $agentDockerfile.Contains('integration/portfolio-profile-contract') -or
    $node24Dockerfile.Contains('integration/portfolio-profile-contract') -or
    $playwrightDockerfile.Contains('integration/portfolio-profile-contract') -or
    $secondaryPlaywrightDockerfile.Contains('integration/portfolio-profile-contract') -or
    -not $portfolioConsumerPackage.Contains('"node": ">=22.23.3"') -or
    -not $portfolioConsumerDocs.Contains('not yet wired into a live Jenkins job') -or
    -not $portfolioAdapterDocs.Contains('No Jenkins job') -or
    -not $portfolioAdapterDocs.Contains('no App token is fetched') -or
    -not $portfolioAdapterDocs.Contains('GitHub''s API immediately before invoking') -or
    -not $portfolioAdapterDocs.Contains('controller image; the agent images do not include it') -or
    -not $portfolioConsumerDocs.Contains('Fork PRs are rejected')) {
    throw 'The portfolio profile consumer must remain data-only, tested, Node 22-compatible, and explicitly non-qualified until runtime wiring and isolation are verified.'
}

Write-Output 'Compose isolation, disposable Node 22/Node 24/Playwright agents, controller-before-checkout authorization, opt-in secondary-repository profile, separate verification lanes, credential boundaries, check reporting, recovery gates, trusted-pipeline contracts, Test Platform consumer contract, and bounded controller-side portfolio profile adapter contract passed.'
