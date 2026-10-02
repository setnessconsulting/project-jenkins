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
$node2214DockerfilePath = Join-Path $repositoryRoot 'agent/Node22.14.Dockerfile'
$node2214DisposableDockerfilePath = Join-Path $repositoryRoot 'agent/Node22.14Disposable.Dockerfile'
$setnessWebCIDockerfilePath = Join-Path $repositoryRoot 'agent/SetnessWebCI.Dockerfile'
$node24DockerfilePath = Join-Path $repositoryRoot 'agent/Node24.Dockerfile'
$python312DockerfilePath = Join-Path $repositoryRoot 'agent/Python312.Dockerfile'
$gameMakerPythonMatrixDockerfilePath = Join-Path $repositoryRoot 'agent/GameMakerPythonMatrix.Dockerfile'
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
$portfolioPipelinePath = Join-Path $repositoryRoot 'casc/pipelines/portfolio-pr-gate.groovy'
$portfolioPollerPipelinePath = Join-Path $repositoryRoot 'casc/pipelines/portfolio-pr-poller.groovy'
$portfolioCredentialHelpersPath = Join-Path $repositoryRoot 'casc/pipelines/portfolio-credential-store.groovy'
$portfolioReaperPipelinePath = Join-Path $repositoryRoot 'casc/pipelines/portfolio-checkout-credential-reaper.groovy'
$groovySyntaxVerifierPath = Join-Path $repositoryRoot 'scripts/verify-groovy-syntax.ps1'
$groovySyntaxFixturePath = Join-Path $repositoryRoot 'scripts/verify-groovy-syntax.groovy'
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
$portfolioPollerCliPath = Join-Path $repositoryRoot 'integration/portfolio-profile-contract/src/plan-poll.mjs'
$portfolioPollerTestsPath = Join-Path $repositoryRoot 'integration/portfolio-profile-contract/test/plan-poll.test.mjs'
$portfolioPollerCliTestsPath = Join-Path $repositoryRoot 'integration/portfolio-profile-contract/test/plan-poll-cli.test.mjs'
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
$node2214Dockerfile = Get-Content -LiteralPath $node2214DockerfilePath -Raw
$node2214DisposableDockerfile = Get-Content -LiteralPath $node2214DisposableDockerfilePath -Raw
$setnessWebCIDockerfile = Get-Content -LiteralPath $setnessWebCIDockerfilePath -Raw
$node24Dockerfile = Get-Content -LiteralPath $node24DockerfilePath -Raw
$python312Dockerfile = Get-Content -LiteralPath $python312DockerfilePath -Raw
$gameMakerPythonMatrixDockerfile = Get-Content -LiteralPath $gameMakerPythonMatrixDockerfilePath -Raw
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
$portfolioPipeline = Read-NormalizedText -LiteralPath $portfolioPipelinePath
$portfolioPollerPipeline = Read-NormalizedText -LiteralPath $portfolioPollerPipelinePath
$portfolioCredentialHelpers = Read-NormalizedText -LiteralPath $portfolioCredentialHelpersPath
$portfolioReaperPipeline = Read-NormalizedText -LiteralPath $portfolioReaperPipelinePath
$groovySyntaxVerifier = Read-NormalizedText -LiteralPath $groovySyntaxVerifierPath
$groovySyntaxFixture = Read-NormalizedText -LiteralPath $groovySyntaxFixturePath
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
$portfolioPollerCli = Read-NormalizedText -LiteralPath $portfolioPollerCliPath
$portfolioPollerTests = Read-NormalizedText -LiteralPath $portfolioPollerTestsPath
$portfolioPollerCliTests = Read-NormalizedText -LiteralPath $portfolioPollerCliTestsPath
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
    'Object resolveBranchSourcePullRequestRevision(def run)',
    'factory.getLastSeenRevision(job)',
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
    -not $pilotConfigParser.Contains("'JENKINS_PORTFOLIO_CATALOG_REPOSITORY'") -or
    -not $pilotConfigParser.Contains('PortfolioCatalogRepository = $portfolioCatalogRepository') -or
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
foreach ($privateConfigurationKey in @('JENKINS_GITHUB_APP_CREDENTIAL_ID', 'JENKINS_PORTFOLIO_CATALOG_REPOSITORY', 'JENKINS_CHECKOUT_SSH_CREDENTIAL_ID', 'JENKINS_PRIMARY_CHECK_NAME', 'JENKINS_CANDIDATE_CHECK_NAME', 'JENKINS_APP_DIRECTORY', 'JENKINS_TUTOR_WEB_DIRECTORY', 'JENKINS_E2E_JOB_NAME', 'JENKINS_SITE_URL')) {
    if (-not $compose.Contains($privateConfigurationKey)) {
        throw "Private target configuration must be injected from local runtime settings: $privateConfigurationKey."
    }
}
if (-not $jenkinsConfig.Contains('numExecutors: 1')) {
    throw 'The Jenkins controller must keep exactly one built-in executor so Test Platform Authorize and Finalize can run on label built-in. Zero executors queues those stages forever after a CasC reload.'
}
if ($jenkinsConfig -match 'numExecutors:\s*0') {
    throw 'The Jenkins controller must not return to zero built-in executors; Authorize and Finalize need label built-in.'
}
if (-not $jenkinsConfig.Contains('tmpSpace:') -or -not $jenkinsConfig.Contains('freeSpaceThreshold: "100MB"')) {
    throw 'CasC must keep TemporarySpaceMonitor (tmpSpace) freeSpaceThreshold at 100MB so reload does not offline the node-22.14 canary agent.'
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
    'JENKINS_TEST_PLATFORM_EVIDENCE_ROOT:',
    'JENKINS_PORTFOLIO_CATALOG_REPOSITORY:'
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
    $oneBuildTemplateCapCount -ne 9 -or
    $oneBuildRetentionStrategyCount -ne 9 -or
    $jenkinsConfig.Contains('$class: com.nirima.jenkins.plugins.docker.strategy.DockerOnceRetentionStrategy') -or
    $jenkinsConfig.Contains('dockerOnce:') -or
    -not $jenkinsConfig.Contains('idleMinutes: 0') -or
    -not $jenkinsConfig.Contains('labelString: "setness-ephemeral"') -or
    -not $jenkinsConfig.Contains('removeVolumes: true') -or
    -not $jenkinsConfig.Contains('memoryLimit: 4096') -or
    -not $jenkinsConfig.Contains('memorySwap: 4096') -or
    -not $jenkinsConfig.Contains('cpus: "4.0"') -or
    -not $jenkinsConfig.Contains('privileged: false') -or
    -not $jenkinsConfig.Contains('network: "setness-jenkins-private"')) {
    throw 'The Docker cloud must configure nine correctly bounded one-build templates through the plugin CasC schema and provision resource-limited, unprivileged containers on its private network.'
}
if ($jenkinsConfig.Contains('permanent:') -or $jenkinsConfig.Contains('setness-linux-agent')) {
    throw 'A persistent Jenkins agent must not be configured.'
}
foreach ($agentContract in @(
    'labelString: "setness-web-ci-node22-ephemeral"',
    'image: "jenkins-pilot-agent:setness-web-ci-node22-pwsh-7.6.6"',
    'labelString: "setness-node22-14-ephemeral"',
    'image: "jenkins-pilot-agent:node-22.14.0"',
    'labelString: "setness-node22-14-disposable-ephemeral"',
    'image: "jenkins-pilot-agent:node-22.14.0-disposable"',
    'labelString: "setness-node24-ephemeral"',
    'image: "jenkins-pilot-agent:node-24.21.0"',
    'labelString: "setness-python312-ephemeral"',
    'image: "jenkins-pilot-agent:python-3.12.14"',
    'labelString: "setness-game-maker-python-matrix-ephemeral"',
    'image: "jenkins-pilot-agent:game-maker-python-3.11.17-3.12.14"',
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
    '(?m)^          - name: "setness-web-ci-node22-one-build"\r?\n            labelString: "setness-web-ci-node22-ephemeral"$'
) -or -not $jenkinsConfig.Contains('image: "jenkins-pilot-agent:setness-web-ci-node22-pwsh-7.6.6"') -or
    -not $jenkinsConfig.Contains('memoryLimit: 4096')) {
    throw 'Setness primary CI must use a dedicated one-use, resource-limited Docker agent template.'
}
$setnessWebCITemplateMatch = [regex]::Match(
    $jenkinsConfig,
    '(?ms)^          - name: "setness-web-ci-node22-one-build"\r?\n(?<body>.*?)(?=^          - name: |^  [A-Za-z])'
)
if (-not $setnessWebCITemplateMatch.Success -or
    $setnessWebCITemplateMatch.Groups['body'].Value.Contains('mounts:') -or
    $setnessWebCITemplateMatch.Groups['body'].Value.Contains('docker.sock')) {
    throw 'The Setness primary CI agent must not mount the Docker socket or any host volume.'
}
if (-not [regex]::IsMatch(
    $jenkinsConfig,
    '(?m)^          - name: "secondary-node24-playwright-one-build"\r?\n            labelString: "secondary-node24-playwright-ephemeral"$'
)) {
    throw 'The secondary one-use agent label must remain nested under its Docker template in Jenkins CasC.'
}
if (-not [regex]::IsMatch(
    $jenkinsConfig,
    '(?m)^          - name: "setness-node22-14-one-build"\r?\n            labelString: "setness-node22-14-ephemeral"$'
) -or -not $jenkinsConfig.Contains('image: "jenkins-pilot-agent:node-22.14.0"') -or
    -not $jenkinsConfig.Contains('memoryLimit: 4096')) {
    throw 'The exact Node 22.14 profile must have a dedicated one-use, resource-limited Docker agent template.'
}
$node2214DisposableTemplateMatch = [regex]::Match(
    $jenkinsConfig,
    '(?ms)^          - name: "setness-node22-14-disposable-one-build"\r?\n(?<body>.*?)(?=^          - name: |^  [A-Za-z])'
)
if (-not $node2214DisposableTemplateMatch.Success -or
    -not $node2214DisposableTemplateMatch.Groups['body'].Value.Contains('labelString: "setness-node22-14-disposable-ephemeral"') -or
    -not $node2214DisposableTemplateMatch.Groups['body'].Value.Contains('image: "jenkins-pilot-agent:node-22.14.0-disposable"') -or
    -not $node2214DisposableTemplateMatch.Groups['body'].Value.Contains('network: "setness-jenkins-private"') -or
    -not $node2214DisposableTemplateMatch.Groups['body'].Value.Contains('cpus: "4.0"') -or
    -not $node2214DisposableTemplateMatch.Groups['body'].Value.Contains('memoryLimit: 4096') -or
    -not $node2214DisposableTemplateMatch.Groups['body'].Value.Contains('memorySwap: 4096') -or
    $node2214DisposableTemplateMatch.Groups['body'].Value.Contains('mounts:') -or
    $node2214DisposableTemplateMatch.Groups['body'].Value.Contains('docker.sock')) {
    throw 'The dedicated Node 22.14 disposable agent must stay resource-bounded on the private network without Docker socket or host mounts.'
}
if (-not [regex]::IsMatch(
    $jenkinsConfig,
    '(?m)^          - name: "setness-python312-one-build"\r?\n            labelString: "setness-python312-ephemeral"$'
) -or -not $jenkinsConfig.Contains('image: "jenkins-pilot-agent:python-3.12.14"') -or
    -not $jenkinsConfig.Contains('memoryLimit: 4096')) {
    throw 'The pinned Python 3.12 profile must have a dedicated one-use, resource-limited Docker agent template.'
}
if (-not [regex]::IsMatch(
    $jenkinsConfig,
    '(?m)^          - name: "setness-game-maker-python-matrix-one-build"\r?\n            labelString: "setness-game-maker-python-matrix-ephemeral"$'
) -or -not $jenkinsConfig.Contains('image: "jenkins-pilot-agent:game-maker-python-3.11.17-3.12.14"') -or
    -not $jenkinsConfig.Contains('memoryLimit: 4096')) {
    throw 'The Game Maker matrix profile must have a dedicated one-use, resource-limited Docker agent template.'
}

# The guest Docker socket belongs to the controller alone (Compose) because the
# Docker cloud needs it to create one-use agents. It must never reach an agent:
# docker-plugin reads these CasC mounts when it creates each container, and a
# socket bind hands daemon access (effectively host root) to whatever code the
# agent runs. The controller-side API endpoint is asserted separately below.
$dockerSockMountCount = [regex]::Matches(
    $jenkinsConfig,
    [regex]::Escape('type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock')
).Count
if ($dockerSockMountCount -ne 0 -or
    -not $jenkinsConfig.Contains('uri: "unix:///var/run/docker.sock"')) {
    throw 'No Jenkins agent template may mount the guest Docker socket, and the Docker cloud must keep reaching it on the controller.'
}
foreach ($socketFreeAgentTemplate in @(
    'setness-node22-one-build',
    'setness-node22-14-one-build',
    'setness-game-maker-python-matrix-one-build'
)) {
    $socketFreeTemplateMatch = [regex]::Match(
        $jenkinsConfig,
        '(?ms)^          - name: "' + [regex]::Escape($socketFreeAgentTemplate) + '"\r?\n(?<body>.*?)(?=^          - name: |^  [A-Za-z])'
    )
    if (-not $socketFreeTemplateMatch.Success -or
        $socketFreeTemplateMatch.Groups['body'].Value.Contains('mounts:') -or
        $socketFreeTemplateMatch.Groups['body'].Value.Contains('docker.sock')) {
        throw "The one-use agent template $socketFreeAgentTemplate must stay free of host mounts and the Docker socket."
    }
}
if (-not $vmStartScript.Contains('PORTFOLIO_AGENT_SOCKET_MOUNTS=') -or
    -not $vmStartScript.Contains('grep -q ''^PORTFOLIO_AGENT_SOCKET_MOUNTS=0$''')) {
    throw 'Deploy verification must read back that no agent template receives the Docker socket and fail closed when one does.'
}
# The Node 22 and Node 22.14 images used to ship a pinned Docker CLI and join
# docker GID 988 so they could use the socket that dockerTemplateBase.mounts
# bound into them. Both are gone: the guest socket stays on the controller, no
# template mounts it back in, and a client on an agent could only widen the
# boundary, so the images must stay free of the CLI and the group.
if ($agentDockerfile.Contains('docker-29.8.1') -or
    $agentDockerfile.Contains('download.docker.com') -or
    $agentDockerfile.Contains('/usr/local/bin/docker') -or
    $agentDockerfile.Contains('groupadd --gid 988 docker') -or
    $agentDockerfile.Contains('usermod --append --groups docker jenkins') -or
    $node2214Dockerfile.Contains('docker-29.8.1') -or
    $node2214Dockerfile.Contains('download.docker.com') -or
    $node2214Dockerfile.Contains('/usr/local/bin/docker') -or
    $node2214Dockerfile.Contains('groupadd --gid 988 docker') -or
    $node2214Dockerfile.Contains('usermod --append --groups docker jenkins')) {
    throw 'No Node agent image may ship a Docker CLI or join a docker group; the guest Docker socket stays on the controller and no template mounts it.'
}
if (-not $plugins.Contains('docker-plugin:1327.v9524f1ee134e')) {
    throw 'The Docker cloud plugin must be explicitly version-pinned.'
}
if (-not $plugins.Contains('pipeline-build-step:601.v6d4c6d1a_9dc7')) {
    throw 'The Pipeline build step plugin must be explicitly version-pinned; the portfolio poller queues the gate job with the build step.'
}
$portfolioRequiredCapabilities = @(
    'pipeline-build-step', 'github-checks', 'workflow-cps', 'workflow-basic-steps',
    'workflow-durable-task-step', 'workflow-job', 'workflow-scm-step', 'github-branch-source',
    'docker-plugin', 'build', 'withChecks', 'publishChecks', 'checkout', 'node', 'sh',
    'writeFile', 'readFile', 'timeout', 'echo', 'error'
)
$portfolioRequiredAgentClasses = @(
    'setness-ephemeral', 'setness-node22-14-ephemeral', 'setness-node22-14-disposable-ephemeral',
    'setness-web-ci-node22-ephemeral', 'setness-node24-ephemeral', 'setness-python312-ephemeral',
    'setness-game-maker-python-matrix-ephemeral', 'secondary-node24-playwright-ephemeral'
)
foreach ($requiredCapability in $portfolioRequiredCapabilities) {
    if (-not $portfolioPollerPipeline.Contains("'$requiredCapability'") -or
        -not $vmStartScript.Contains("'$requiredCapability'")) {
        throw "The controller capability preflight must name '$requiredCapability' in both the trusted poller and the deploy-time verification."
    }
}
foreach ($agentClass in $portfolioRequiredAgentClasses) {
    if (-not $portfolioPollerPipeline.Contains("'$agentClass'") -or
        -not $portfolioPipeline.Contains("'$agentClass'") -or
        -not $vmStartScript.Contains("'$agentClass'") -or
        -not $jenkinsConfig.Contains("labelString: `"$agentClass`"")) {
        throw "The poller, gate, deploy-time verification, and CasC templates must keep the supported agent class '$agentClass' aligned."
    }
}
if (-not $portfolioPollerPipeline.Contains('String portfolioPollControllerCapabilityGap(') -or
    -not $portfolioPollerPipeline.Contains("stage('Assert controller capabilities')") -or
    -not $portfolioPollerPipeline.Contains('error(capabilityGap)') -or
    -not $portfolioPollerPipeline.Contains('jenkins.getDescriptorList(org.jenkinsci.plugins.workflow.steps.Step.class)') -or
    -not $portfolioPollerPipeline.Contains('jenkins.getLabelAtom(agentClass.toString())') -or
    -not $portfolioPollerPipeline.Contains('cloud instanceof com.nirima.jenkins.plugins.docker.DockerCloud') -or
    -not $portfolioPollerPipeline.Contains('cloud.canProvision(label)') -or
    -not $portfolioPollerPipeline.Contains('cloud.getTemplates().any { template ->') -or
    -not $portfolioPollerPipeline.Contains('label.matches(template.getLabelSet())') -or
    -not $portfolioPollerPipeline.Contains('!template.getDisabled().isDisabled()') -or
    -not $portfolioPipeline.Contains('boolean portfolioHasProvisionableConfiguredAgentClass(String agentClass)') -or
    -not $portfolioPipeline.Contains('cloud instanceof com.nirima.jenkins.plugins.docker.DockerCloud') -or
    -not $portfolioPipeline.Contains('cloud.canProvision(label)') -or
    -not $portfolioPipeline.Contains('cloud.getTemplates().any { template ->') -or
    -not $portfolioPipeline.Contains('label.matches(template.getLabelSet())') -or
    -not $portfolioPipeline.Contains('!template.getDisabled().isDisabled()') -or
    -not $portfolioPipeline.Contains('if (!portfolioHasProvisionableConfiguredAgentClass(resolvedAgentClass))') -or
    -not $vmStartScript.Contains('jenkins.getLabelAtom(agentClass)') -or
    -not $vmStartScript.Contains('cloud instanceof com.nirima.jenkins.plugins.docker.DockerCloud') -or
    -not $vmStartScript.Contains('cloud.canProvision(label)') -or
    -not $vmStartScript.Contains('cloud.getTemplates().any { template ->') -or
    -not $vmStartScript.Contains('label.matches(template.getLabelSet())') -or
    -not $vmStartScript.Contains('!template.getDisabled().isDisabled()') -or
    -not $portfolioPollerPipeline.Contains('// BEGIN JENKINS_PORTFOLIO_CAPABILITY_PREFLIGHT') -or
    -not $portfolioPollerPipeline.Contains('// END JENKINS_PORTFOLIO_CAPABILITY_PREFLIGHT')) {
    throw 'The portfolio poller must fail closed at startup, naming missing plugins, Pipeline steps, trusted resources, or usable agent templates before dispatch; the gate must reject a missing profile-specific template before requesting a node, and keep the delimited preflight block the read-only live probe evaluates.'
}
if (-not $vmStartScript.Contains("println 'PORTFOLIO_CAPABILITIES=' +") -or
    -not $vmStartScript.Contains('grep -q ''^PORTFOLIO_CAPABILITIES=ok$''')) {
    throw 'Deploy verification must report the portfolio dispatch capability set and fail closed when it is incomplete.'
}
if (-not $agentDockerfile.Contains('openssh-client') -or
    -not $agentDockerfile.Contains('agent/known_hosts') -or
    -not $knownHosts.Contains('github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl')) {
    throw 'The SSH checkout agent must include the pinned GitHub host key and SSH client.'
}
if (-not $agentDockerfile.Contains('v22.23.3') -or
    $agentDockerfile.Contains('docker.sock') -or
    -not $node2214Dockerfile.Contains('v22.14.0') -or
    -not $node2214Dockerfile.Contains('npm --version') -or
    -not $node2214Dockerfile.Contains('10.9.2') -or
    -not $node2214Dockerfile.Contains('69b09dba5c8dcb05c4e4273a4340db1005abeafe3927efda2bc5b249e80437ec') -or
    -not $node2214Dockerfile.Contains('sha256sum --check --strict') -or
    -not $node2214Dockerfile.Contains('gitleaks_8.24.3_linux_x64.tar.gz') -or
    -not $node2214Dockerfile.Contains('9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c') -or
    -not $node2214Dockerfile.Contains('install -o root -g root -m 0755 /tmp/gitleaks /usr/local/bin/gitleaks') -or
    -not $node2214Dockerfile.Contains('USER jenkins') -or
    $node2214Dockerfile.Contains('docker.sock') -or
    $node2214Dockerfile.Contains('JENKINS_SECRET') -or
    $node2214Dockerfile.Contains('GITHUB_APP') -or
    -not $node24Dockerfile.Contains('v24.21.0') -or
    -not $node24Dockerfile.Contains('sha256sum --check --strict') -or
    -not $playwrightDockerfile.Contains('PLAYWRIGHT_VERSION=1.62.1') -or
    -not $playwrightDockerfile.Contains('playwright install-deps chromium') -or
    -not $playwrightDockerfile.Contains('playwright install chromium') -or
    -not $playwrightDockerfile.Contains('USER jenkins')) {
    throw 'The pinned Node 22, Node 22.14/Gitleaks, Node 24, and pre-baked unprivileged Playwright agent images are incomplete.'
}
if (-not $node2214DisposableDockerfile.Contains('v22.14.0') -or
    -not $node2214DisposableDockerfile.Contains('npm --version') -or
    -not $node2214DisposableDockerfile.Contains('10.9.2') -or
    -not $node2214DisposableDockerfile.Contains('69b09dba5c8dcb05c4e4273a4340db1005abeafe3927efda2bc5b249e80437ec') -or
    -not $node2214DisposableDockerfile.Contains('sha256sum --check --strict') -or
    -not $node2214DisposableDockerfile.Contains('gitleaks_8.24.3_linux_x64.tar.gz') -or
    -not $node2214DisposableDockerfile.Contains('9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c') -or
    -not $node2214DisposableDockerfile.Contains('install -o root -g root -m 0755 /tmp/gitleaks /usr/local/bin/gitleaks') -or
    -not $node2214DisposableDockerfile.Contains('USER jenkins') -or
    $node2214DisposableDockerfile.Contains('/usr/local/bin/docker') -or
    $node2214DisposableDockerfile.Contains('groupadd --gid 988 docker') -or
    $node2214DisposableDockerfile.Contains('docker-29.8.1') -or
    $node2214DisposableDockerfile.Contains('docker.sock') -or
    $node2214DisposableDockerfile.Contains('JENKINS_SECRET') -or
    $node2214DisposableDockerfile.Contains('GITHUB_APP')) {
    throw 'The dedicated Node 22.14 image must pin its official Node/Gitleaks archives and contain no Docker CLI, socket, or build credentials.'
}
if (-not $compose.Contains('dockerfile: agent/Node22.14Disposable.Dockerfile') -or
    -not $compose.Contains('image: jenkins-pilot-agent:node-22.14.0-disposable')) {
    throw 'Compose must build the separate pinned Node 22.14 disposable agent image.'
}
if (-not $setnessWebCIDockerfile.Contains('v22.23.3') -or
    -not $setnessWebCIDockerfile.Contains('df450af89261115ef9f9e3830c3eeb2cc9213b63c720b1af623cb5dcbe2e02de') -or
    -not $setnessWebCIDockerfile.Contains('powershell-lts_7.6.6-1.deb_amd64.deb') -or
    -not $setnessWebCIDockerfile.Contains('40445854085082B23624D7E437EF17D89DD9C67A72895843297EEAFD5D0163DE') -or
    -not $setnessWebCIDockerfile.Contains('npm --version') -or
    -not $setnessWebCIDockerfile.Contains('10.9.9') -or
    -not $setnessWebCIDockerfile.Contains('pwsh --version') -or
    -not $setnessWebCIDockerfile.Contains('PowerShell 7.6.6') -or
    -not $setnessWebCIDockerfile.Contains('USER jenkins') -or
    $setnessWebCIDockerfile.Contains('docker.sock') -or
    $setnessWebCIDockerfile.Contains('/usr/local/bin/docker') -or
    $setnessWebCIDockerfile.Contains('JENKINS_SECRET') -or
    $setnessWebCIDockerfile.Contains('GITHUB_APP')) {
    throw 'The Setness primary CI image must pin Node/npm and PowerShell, remain unprivileged, and contain no Docker or controller credentials.'
}
if (-not $python312Dockerfile.Contains('ARG PYTHON_VERSION=3.12.14') -or
    -not $python312Dockerfile.Contains('Python-${PYTHON_VERSION}.tar.xz') -or
    -not $python312Dockerfile.Contains('5c8462af5790baf43a321a1559dbe0db06d1be4300fb85fb53c40060668e548a') -or
    -not $python312Dockerfile.Contains('sha256sum --check --strict') -or
    -not $python312Dockerfile.Contains('--enable-shared --with-ensurepip=install') -or
    -not $python312Dockerfile.Contains('Python ${PYTHON_VERSION}') -or
    -not $python312Dockerfile.Contains('USER jenkins') -or
    $python312Dockerfile.Contains('docker.sock') -or
    $python312Dockerfile.Contains('JENKINS_SECRET') -or
    $python312Dockerfile.Contains('GITHUB_APP')) {
    throw 'The Python 3.12 agent must pin and verify the official source runtime, remain unprivileged, and contain no controller or credential access.'
}
if (-not $gameMakerPythonMatrixDockerfile.Contains('ARG PYTHON311_VERSION=3.11.17') -or
    -not $gameMakerPythonMatrixDockerfile.Contains('ARG PYTHON311_SOURCE_SHA256=bfb74ad39efae27cda510f134ab408e00f9992c56851cfc0b1cdb5646da11599') -or
    -not $gameMakerPythonMatrixDockerfile.Contains('ARG PYTHON312_VERSION=3.12.14') -or
    -not $gameMakerPythonMatrixDockerfile.Contains('5c8462af5790baf43a321a1559dbe0db06d1be4300fb85fb53c40060668e548a') -or
    -not $gameMakerPythonMatrixDockerfile.Contains('sha256sum --check --strict') -or
    -not $gameMakerPythonMatrixDockerfile.Contains('python3.11 --version') -or
    -not $gameMakerPythonMatrixDockerfile.Contains('python --version') -or
    -not $gameMakerPythonMatrixDockerfile.Contains('USER jenkins') -or
    $gameMakerPythonMatrixDockerfile.Contains('docker.sock') -or
    $gameMakerPythonMatrixDockerfile.Contains('JENKINS_SECRET') -or
    $gameMakerPythonMatrixDockerfile.Contains('GITHUB_APP')) {
    throw 'The Game Maker matrix agent must pin both official source runtimes, verify their hashes and versions, remain unprivileged, and contain no controller or credential access.'
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
if (-not $compose.Contains('dockerfile: agent/Node22.14.Dockerfile') -or
    -not $compose.Contains('dockerfile: agent/SetnessWebCI.Dockerfile') -or
    -not $compose.Contains('jenkins-pilot-agent:setness-web-ci-node22-pwsh-7.6.6') -or
    -not $compose.Contains('jenkins-pilot-agent:node-22.14.0') -or
    -not $compose.Contains('dockerfile: agent/Node24.Dockerfile') -or
    -not $compose.Contains('dockerfile: agent/Playwright.Dockerfile') -or
    -not $compose.Contains('dockerfile: agent/Node24Playwright.Dockerfile') -or
    -not $compose.Contains('jenkins-pilot-agent:node-24.21.0') -or
    -not $compose.Contains('jenkins-pilot-agent:node-22.23.3-playwright-1.62.1') -or
    -not $compose.Contains('jenkins-pilot-agent:node-24.21.0-playwright-1.62.1') -or
    -not $compose.Contains('dockerfile: agent/Python312.Dockerfile') -or
    -not $compose.Contains('jenkins-pilot-agent:python-3.12.14') -or
    -not $compose.Contains('dockerfile: agent/GameMakerPythonMatrix.Dockerfile') -or
    -not $compose.Contains('jenkins-pilot-agent:game-maker-python-3.11.17-3.12.14')) {
    throw 'Compose must define the buildable pinned Node, Playwright, and Python agent profiles.'
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
if (-not $vmStartScript.Contains('docker image inspect ''jenkins-pilot-agent:node-22.14.0''') -or
    -not $vmStartScript.Contains('build node22-14-agent-image')) {
    throw 'A normal VM start must build the new Node 22.14 agent image when it is not already present.'
}
if (-not $vmStartScript.Contains('docker image inspect ''jenkins-pilot-agent:node-22.14.0-disposable''') -or
    -not $vmStartScript.Contains('build node22-14-disposable-agent-image')) {
    throw 'A normal VM start must build the no-socket Node 22.14 agent image when it is not already present.'
}
if (-not $vmStartScript.Contains('docker image inspect ''jenkins-pilot-agent:setness-web-ci-node22-pwsh-7.6.6''') -or
    -not $vmStartScript.Contains('build setness-web-ci-agent-image')) {
    throw 'A normal VM start must build the Setness primary CI agent when its pinned image is not present.'
}
if (-not $vmStartScript.Contains('portfolio_verify()') -or
    -not $vmStartScript.Contains('  verify)') -or
    -not $vmStartScript.Contains('PORTFOLIO_JOB') -or
    -not $vmStartScript.Contains('isScriptApproved(script, groovyLanguage)') -or
    -not $vmStartScript.Contains('{init-secrets|install|start|restart|stop|status|logs|verify}')) {
    throw 'The VM start script must expose an explicit portfolio verification action that reports the approval state of every loaded job.'
}
if (-not $vmStartScript.Contains('This never approves anything itself') -or
    -not $vmStartScript.Contains('the controller did not report a portfolio posture')) {
    throw 'Portfolio verification must fail closed when the controller reports no posture and must never approve controller code itself.'
}
$portfolioStartArmIndex = $vmStartScript.IndexOf('start|install|restart)')
$portfolioStopArmIndex = $vmStartScript.IndexOf('  stop)')
if ($portfolioStartArmIndex -lt 0 -or $portfolioStopArmIndex -le $portfolioStartArmIndex) {
    throw 'The VM start script must keep the stop action after the start/install/restart arm.'
}
$portfolioStartArm = $vmStartScript.Substring($portfolioStartArmIndex, $portfolioStopArmIndex - $portfolioStartArmIndex)
if (-not $portfolioStartArm.Contains('portfolio_verify')) {
    throw 'Provisioning and restart must run portfolio verification after the controller starts.'
}
if (-not $vmStartScript.Contains('--netrc-file "$netrc_file"') -or
    -not $vmStartScript.Contains('--data-urlencode "script@${script_file}"') -or
    $vmStartScript.Contains('--user "jenkins-admin:${admin_password}"')) {
    throw 'Portfolio verification must hand the administrator secret and the probe body to curl by file so neither appears in the process table.'
}
if (-not $vmStartScript.Contains('PORTFOLIO_SUMMARY loaded=') -or
    -not $vmStartScript.Contains('^PORTFOLIO_SUMMARY loaded=0 ')) {
    throw 'Portfolio verification must report a loaded/approved summary and give an explicit pass for a controller with no loaded portfolio job.'
}
# The dispatch trio is not the whole fleet. CasC also loads the multibranch
# projects with one branch job per branch, the E2E and Test Platform pipelines,
# and the retired root-level gate; a deploy that reports green while one of those
# waits for script approval hides a trusted job that cannot build at all.
if (-not $vmStartScript.Contains('FLEET_JOB ') -or
    -not $vmStartScript.Contains('FLEET_PROJECT ') -or
    -not $vmStartScript.Contains('FLEET_PENDING_SCRIPT index=') -or
    -not $vmStartScript.Contains('FLEET_SUMMARY jobs=') -or
    -not $vmStartScript.Contains('grep -E ''^(PORTFOLIO_|FLEET_)''')) {
    throw 'Portfolio verification must report a fleet-wide inventory (every CasC-managed job, each multibranch branch job and the pending script-security queue) and print it next to the dispatch trio lines.'
}
if (-not $vmStartScript.Contains("getDeclaredField('script')")) {
    throw 'The fleet inventory must read inline branch scripts through the private script field, otherwise every multibranch branch job would report no-script and the inventory would hide exactly the jobs it exists to expose.'
}
# The inventory is report-only by operator decision: a legitimate render change
# leaves jobs waiting for approval, and gating a deploy on that would wedge it,
# while the affected job already fails closed at run time. The dispatch gate
# stays anchored to its own PORTFOLIO_JOB lines so the inventory can never become
# an accidental deploy gate.
if (-not $vmStartScript.Contains('Fleet posture above is informational') -or
    -not $vmStartScript.Contains('grep -q ''^PORTFOLIO_JOB .* script=unapproved$''') -or
    $vmStartScript.Contains("grep -q 'script=unapproved'")) {
    throw 'The fleet inventory must stay report-only, and the portfolio approval gate must read PORTFOLIO_JOB lines only so a report-only inventory can never fail a deployment.'
}
if (-not $vmStartScript.Contains('the controller is already running') -or
    -not $vmStartScript.Contains('there is nothing to verify')) {
    throw 'Portfolio verification must state its own install/restart exit semantics and its no-loaded-job posture.'
}
if (-not $vmStartScript.Contains('build controller agent-image node22-14-agent-image node22-14-disposable-agent-image setness-web-ci-agent-image node24-agent-image python312-agent-image game-maker-python-matrix-agent-image e2e-agent-image secondary-agent-image')) {
    throw 'VM installation and restart must prebuild every disposable agent profile.'
}
if (-not $vmStartScript.Contains("docker image inspect 'jenkins-pilot-agent:python-3.12.14'")) {
    throw 'A normal VM start must build the Python agent image if the pinned runtime is missing.'
}
if (-not $vmStartScript.Contains("docker image inspect 'jenkins-pilot-agent:game-maker-python-3.11.17-3.12.14'")) {
    throw 'A normal VM start must build the Game Maker matrix agent image if either pinned runtime is missing.'
}
foreach ($agentImage in @(
    'jenkins-pilot-agent:node-22.23.3',
    'jenkins-pilot-agent:node-22.14.0',
    'jenkins-pilot-agent:node-22.14.0-disposable',
    'jenkins-pilot-agent:setness-web-ci-node22-pwsh-7.6.6',
    'jenkins-pilot-agent:node-24.21.0',
    'jenkins-pilot-agent:python-3.12.14',
    'jenkins-pilot-agent:game-maker-python-3.11.17-3.12.14',
    'jenkins-pilot-agent:node-22.23.3-playwright-1.62.1',
    'jenkins-pilot-agent:node-24.21.0-playwright-1.62.1'
)) {
    if (-not $backupScript.Contains($agentImage) -or -not $restoreScript.Contains($agentImage)) {
        throw "Backup and restore safety checks must account for every disposable agent image: $agentImage."
    }
}
if ($backupScript.IndexOf('export GIT_OPTIONAL_LOCKS=0') -lt 0 -or
    $backupScript.IndexOf('export GIT_OPTIONAL_LOCKS=0') -gt $backupScript.IndexOf('git -c safe.directory=')) {
    throw 'The root-only Jenkins backup must not refresh the guest-owned Git index and change checkout ownership.'
}
if ($restoreScript.IndexOf('export GIT_OPTIONAL_LOCKS=0') -lt 0 -or
    $restoreScript.IndexOf('export GIT_OPTIONAL_LOCKS=0') -gt $restoreScript.IndexOf('git -c safe.directory=')) {
    throw 'The root-only Jenkins restore drill must not refresh the guest-owned Git index and change checkout ownership.'
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
    'git rev-parse HEAD',
    'src/cli.mjs',
    'JsonSlurperClassic',
    "label 'built-in'",
    'testPlatformAgentClassAllowed(agentClass)',
    'node(agentClass)',
    'cleanupSucceeded = true',
    'setness-node24-ephemeral',
    'setness-e2e-ephemeral',
    "exitCode == 0 ? 'passed'",
    'env.GIT_COMMIT = checkedOutSha',
    'archiveArtifacts',
    'JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson'
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
if ($testPlatformPipeline.Contains("label 'setness-node22-14-ephemeral'") -or
    -not $testPlatformPipeline.Contains("['setness-ephemeral', 'setness-node24-ephemeral', 'setness-e2e-ephemeral'].contains(agentClass)")) {
    throw 'Each approved Test Platform suite must run on its centrally resolved agent class, restricted to the controller allowlist.'
}
if ($testPlatformPipeline.Contains('BodyInvoker') -or $testPlatformPipeline.Contains('readJSON')) {
    throw 'The Test Platform pipeline must keep the live canary script: FlowInterruptedException plus ABORTED, and JsonSlurperClassic, not BodyInvoker or readJSON.'
}
$testPlatformCatalog = $testPlatformCatalog | ConvertFrom-Json
if ($testPlatformCatalog.executor_profiles.'node-22-deterministic'.workspace -ne '.') {
    throw 'The node-22-deterministic catalog workspace must stay at the repository root (.).'
}
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
foreach ($executorId in @('node-22-deterministic', 'node-24-deterministic', 'browser-e2e')) {
    if ($null -eq $testPlatformCatalog.executors.$executorId) {
        throw "The approved Test Platform catalog is missing the approved executor: $executorId."
    }
}
foreach ($socketFreeExecutorId in @('node-22-deterministic', 'node-24-deterministic', 'browser-e2e')) {
    if ($testPlatformCatalog.executors.$socketFreeExecutorId.capabilities -contains 'docker' -or
        $testPlatformCatalog.executor_profiles.$socketFreeExecutorId.argv -contains 'docker') {
        throw "No approved Test Platform executor may claim Docker capability: $socketFreeExecutorId."
    }
}
foreach ($suiteId in @('standard', 'typecheck', 'tutor-web', 'e2e')) {
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
if (-not $jobs.Contains("pipelineJob('portfolio-dispatch/portfolio-pr-gate')") -or
    -not $jobs.Contains('portfolioPipelineTemplate') -or
    -not $jobs.Contains('disabled(!portfolioCatalogEnabled)') -or
    -not $jobs.Contains("pipelineJob('portfolio-dispatch/portfolio-checkout-credential-reaper')") -or
    -not $jobs.Contains("cron('H/15 * * * *')") -or
    -not $jobs.Contains("pipelineJob('portfolio-pr-gate')") -or
    -not $jobs.Contains('disabled(true)') -or
    -not $jobs.Contains('Deprecated root-level dispatcher')) {
    throw 'The portfolio dispatcher must be folder-scoped, disabled when catalog configuration is absent, and paired with a scheduled credential reaper; the legacy root job must be disabled.'
}
if (-not $portfolioPipeline.Contains("profile.status in ['shadow', 'qualified']")) {
    throw 'The portfolio PR gate must accept both shadow and already-qualified profiles selected by the controller poller.'
}
$portfolioPullRequestIdentityIndex = $portfolioPipeline.IndexOf('if (pullRequest.number != pullRequestNumber')
$portfolioCheckCreationIndex = $portfolioPipeline.IndexOf('Map check = portfolioCreateCheck(currentBuild.rawBuild, portfolioAppCredentialId, repository, expectedSha)')
$portfolioCatalogReadIndex = $portfolioPipeline.IndexOf('Map catalogRef = portfolioRepoApiRequest(')
$portfolioResolverIndex = $portfolioPipeline.IndexOf('Map resolved = portfolioResolveProfile(')
if ($portfolioPullRequestIdentityIndex -lt 0 -or
    $portfolioCheckCreationIndex -le $portfolioPullRequestIdentityIndex -or
    $portfolioCatalogReadIndex -le $portfolioCheckCreationIndex -or
    $portfolioResolverIndex -le $portfolioCheckCreationIndex -or
    -not $portfolioPipeline.Contains("env.PORTFOLIO_STATE = 'CHECK_PENDING'") -or
    -not $portfolioPipeline.Contains('if (checkId) {')) {
    throw 'After live same-repository PR identity is confirmed, the exact-SHA Jenkins check must be created before profile resolution and finalized visibly even when authorization fails.'
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
    "'setness-web-ci-node22-v1'",
    "agentClass: 'setness-web-ci-node22-ephemeral'",
    "Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'pwsh', '-File', 'scripts/verify-jenkins-fallback-contract.ps1'])",
    "Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'node', 'scripts/test-jenkins-fallback-runtime.mjs'])",
    "Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'ci'])",
    "Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'typecheck'])",
    "Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'lint'])",
    "Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'build'])",
    "Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'blog:validate'])",
    "Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'seo:baseline'])",
    "Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'test'])",
    "'node22-foundation-v1'",
    "nodeVersion: '22.23.3'",
    "npmVersion: '10.9.9'",
    "'node22-github-api-foundation-v1'",
    "Object.freeze(['npm', 'ci', '--ignore-scripts'])",
    "'jenkins-repository-contract'",
    "integration/portfolio-profile-contract/test/consumer.test.mjs",
    "Object.freeze(['node', '--test', 'integration/test-platform-contract/test/adapter.test.mjs'])",
    "'node24-lint-typescript-test-v1'",
    "agentClass: 'setness-node24-ephemeral'",
    "nodeVersion: '24.21.0'",
    "'node24-game-platform-sdk-v1'",
    "Object.freeze(['npm', 'run', 'verify:bundle'])",
    "'node24-game-planetary-survey-v1'",
    "Object.freeze(['npm', 'run', 'verify'])",
    "'node24-game-fraction-match-full-ci-v1'",
    "'game-fraction-match-node24-full-ci'",
    "'setnessconsulting/game-fraction-match'",
    "Object.freeze(['npm', 'run', 'test:coverage'])",
    "Object.freeze(['npm', 'run', 'check:architecture'])",
    "Object.freeze(['npm', 'run', 'check:privacy'])",
    "Object.freeze(['npm', 'run', 'test:e2e:run'])",
    "Object.freeze(['npm', 'run', 'test:host:run'])",
    "'node24-curiouspathway-pilot-v1'",
    "agentClass: 'secondary-node24-playwright-ephemeral'",
    "Object.freeze(['npm', 'ci', '--no-audit', '--no-fund'])",
    "Object.freeze(['npm', 'run', 'test:math-escape-preservation'])",
    "'tests/wave1/e2e/foundation.spec.ts'",
    "'tests/wave6/e2e/noGames.spec.ts'",
    "'tests/wave7/e2e/qualification.spec.ts'",
    "'python312-test-platform-v1'",
    "agentClass: 'setness-python312-ephemeral'",
    "pythonVersion: '3.12.14'",
    "Object.freeze(['python', '-m', 'pip', 'install', '-e', '.[dev]'])",
    "Object.freeze(['python', '-m', 'test_platform.verify'])",
    "'python312-playtest-lab-v1'",
    "Object.freeze(['python', '-m', 'pip', 'install', '--upgrade', 'pip'])",
    "Object.freeze(['python', '-m', 'pip', 'install', '.[test]'])",
    "Object.freeze(['mkdir', '-p', '.frameworks'])",
    "'https://github.com/gameworld-project/GameWorld.git'",
    "'3c26bdab436800fd61ef40543b64ca40d12c7e4a'",
    "Object.freeze(['python', '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py', '-v'])",
    "'python312-cloudflare-api-uv-v1'",
    "Object.freeze(['python', '-m', 'pip', 'install', '--disable-pip-version-check', 'uv==0.11.17'])",
    "Object.freeze(['uv', 'sync', '--locked', '--extra', 'dev'])",
    "Object.freeze(['uv', 'run', 'python', 'scripts/verify.py'])",
    "Object.freeze(['uv', 'run', 'cloudflare-api', 'doctor', '--json'])",
    "'python312-portfolio-graph-uv-v1'",
    "Object.freeze(['uv', 'run', '--locked', 'python', 'scripts/verify.py'])",
    "Object.freeze(['uv', 'run', '--locked', 'portfolio', 'doctor', '--json'])",
    "'python312-blender-api-v1'",
    "Object.freeze(['python', '-m', 'pip', 'install', '--require-hashes', '-r', 'requirements-lock-linux-py312.txt'])",
    "'python312-fmod-api-v1'",
    "Object.freeze(['python', 'scripts/generate_scripting_api.py', '--check'])",
    "'python312-game-maker-v1'",
    "Object.freeze(['python', '-m', 'game_maker', '--version'])",
    "'python312-context-file-maker-v1'",
    "Object.freeze(['python', 'scripts/validate.py', '--strict'])",
    "'python312-cpa-ai-pack-v1'",
    '2dd103d7624c1021d19f04a8b4a64fae38c2e26935cba425f88fe1a9d0a2af2c',
    'edac0d21deb04df402e2c8715eaacfe9d4f60aaa0e31be242fd540619b157de5',
    'commands: Object.freeze([',
    "Object.freeze(['npm', 'run', 'check'])",
    "Object.freeze(['npm', 'test'])",
    "Object.freeze(['npm', 'run', 'lint'])",
    "Object.freeze(['node_modules/.bin/tsc', '--noEmit'])",
    "'node2214-vercel-api-gitleaks-v1'",
    "'node2214-unity-api-maintenance-v1'",
    "agentClass: 'setness-node22-14-disposable-ephemeral'",
    "nodeVersion: '22.14.0'",
    "npmVersion: '10.9.2'",
    "Object.freeze(['npm', 'ci', '--ignore-scripts'])",
    "Object.freeze(['npm', 'run', 'check'])",
    "'gitleaks', 'dir', '--redact', '--exit-code', '1',",
    "'--report-format', 'sarif', '--report-path', '/tmp/gitleaks.sarif', '.'",
    "Object.freeze(['npm', 'ci'])",
    "Object.freeze(['npm', 'run', 'maintenance'])",
    'const FIXED_IMPLEMENTATION_REPOSITORIES = Object.freeze({',
    "'node24-game-fraction-match-full-ci-v1': 'setnessconsulting/game-fraction-match'",
    "'python312-game-maker-v1': 'setnessconsulting/project-game-maker'",
    "reject('implementation-repository-mismatch',",
    'const FIXED_IMPLEMENTATION_PROFILE_IDS = Object.freeze({',
    "'node24-game-fraction-match-full-ci-v1': 'game-fraction-match-node24-full-ci'",
    "'python312-game-maker-v1': 'project-game-maker-python312'",
    "reject('implementation-profile-mismatch',",
    "'setnessconsulting/project-unity-api'",
    'export function validateProfileCatalog(catalog)',
    'function resolveShadowExecution(catalog, profileId, headSha)',
    'export function resolveAuthorizedShadowPullRequest(',
    "execution.repository.toLowerCase() !== verified.repository.toLowerCase()",
    "if (!['shadow', 'qualified'].includes(profile.status))",
    'if (implementation.nodeVersion)',
    'profile.requiredPythonVersion !== implementation.pythonVersion',
    'pythonVersion: implementation.pythonVersion',
    'additionalPythonVersion: implementation.additionalPythonVersion',
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
foreach ($portfolioRuntimeGuard in @(
    'def portfolioCatalogRepository = /* JENKINS_PORTFOLIO_CATALOG_REPOSITORY */',
    "def portfolioCatalogPath = 'profiles/profiles.json'",
    "def portfolioAdapterImplementationAllowlist = [",
    "'setness-web-ci-node22-v1'",
    "'node22-foundation-v1'",
    "'node22-verify-clean-checkout-v1'",
    "'jenkins-repository-contract'",
    "'node24-game-platform-sdk-v1'",
    "'node24-game-planetary-survey-v1'",
    "'node24-game-fraction-match-full-ci-v1'",
    "'node24-curiouspathway-pilot-v1'",
    "'python312-portfolio-graph-uv-v1'",
    "'python312-test-platform-v1'",
    "'python312-playtest-lab-v1'",
    "'python312-cloudflare-api-uv-v1'",
    "'python312-blender-api-v1'",
    "'python312-fmod-api-v1'",
    "'python312-game-maker-v1'",
    'env.PORTFOLIO_ADDITIONAL_PYTHON_VERSION = resolved.additionalPythonVersion?.toString() ?:',
    'EXPECTED_ADDITIONAL_PYTHON_VERSION=${env.PORTFOLIO_ADDITIONAL_PYTHON_VERSION}',
    'test "$(python3.11 --version)" = "Python $EXPECTED_ADDITIONAL_PYTHON_VERSION"',
    "'python312-context-file-maker-v1'",
    "'python312-cpa-ai-pack-v1'",
    "'node2214-vercel-api-gitleaks-v1'",
    "'node2214-unity-api-maintenance-v1'",
    "'node22-github-api-foundation-v1'",
    "!(resolvedAgentClass in ['setness-ephemeral', 'setness-node22-14-ephemeral', 'setness-node22-14-disposable-ephemeral', 'setness-web-ci-node22-ephemeral', 'setness-node24-ephemeral', 'setness-python312-ephemeral', 'setness-game-maker-python-matrix-ephemeral', 'secondary-node24-playwright-ephemeral'])",
    'resolved.pythonVersion.toString() == profile.requiredPythonVersion?.toString()',
    'env.PORTFOLIO_NODE_VERSION = resolved.nodeVersion?.toString() ?:',
    'env.PORTFOLIO_PYTHON_VERSION = resolved.pythonVersion?.toString() ?:',
    'env.PORTFOLIO_NPM_VERSION = resolved.npmVersion?.toString() ?:',
    'test "$(node --version)" = "$EXPECTED_NODE_VERSION"',
    'test "$(python --version)" = "Python $EXPECTED_PYTHON_VERSION"',
    'test "$(npm --version)" = "$EXPECTED_NPM_VERSION"',
    'portfolioScopedAppToken(def run, String credentialId, String repository, Map permissions)',
    'new org.jenkinsci.plugins.github_branch_source.app_credentials.AccessSpecifiedRepositories(parts[0], [parts[1]])',
    'portfolioFolderCredentialStore(run)',
    'store.addCredentials(domain, credential)',
    'if (!partial.is(credential)',
    'store.removeCredentials(domain, partial)',
    'Temporary checkout credential setup failed and rollback could not be confirmed',
    'Map portfolioRepoApiRequest(',
    'Map portfolioFetchJsonFile(',
    'Map portfolioResolveProfile(',
    'portfolioCleanupStaleCheckoutCredentials(currentBuild.rawBuild, 65 * 60 * 1000L)',
    'Map refreshedPullRequest = portfolioRepoApiRequest(',
    'temporaryCheckoutCredentialId = portfolioCreateCheckoutCredential(',
    'portfolioRemoveCheckoutCredential(currentBuild.rawBuild, temporaryCheckoutCredentialId)',
    'refs/pull/${params.PULL_REQUEST_NUMBER}/head:refs/remotes/origin/pull/${params.PULL_REQUEST_NUMBER}/head',
    'checkedOutSha != env.PORTFOLIO_HEAD_SHA.toLowerCase()',
    "name: 'jenkins-pr-gate'",
    'portfolioCreateCheck(currentBuild.rawBuild',
    'portfolioCompleteCheck(',
    'portfolioAppCredentialId',
    "node(env.PORTFOLIO_AGENT_CLASS)",
    'disableConcurrentBuilds()',
    "PORTFOLIO_STATE = 'AUTHORIZED'",
    'Actions remains authoritative'
)) {
    if (-not $portfolioPipeline.Contains($portfolioRuntimeGuard)) {
        throw "The manual portfolio controller dispatcher is missing a required scope, exact-SHA, or cleanup boundary: $portfolioRuntimeGuard"
    }
}
$portfolioArtifactPattern = "archiveArtifacts artifacts: 'dist/**,coverage/coverage-summary.json,coverage/lcov.info,test-results/**,playwright-report/**,playwright-report-host/**'"
$portfolioArtifactScopedBlock = "(?s)finally\s*\{\s*try\s*\{\s*if \(env\.PORTFOLIO_PROFILE_ID == 'game-fraction-match-node24-full-ci'\)\s*\{\s*$([regex]::Escape($portfolioArtifactPattern))\s*,\s*allowEmptyArchive: true,\s*onlyIfSuccessful: false\s*\}\s*\}\s*finally\s*\{\s*deleteDir\(\)"
if (-not [regex]::IsMatch($portfolioPipeline, $portfolioArtifactScopedBlock)) {
    throw 'The Fraction Match profile must archive the fixed verification and browser outputs, including failed runs, before unconditional workspace cleanup.'
}
if (-not $portfolioCredentialHelpers.Contains('CredentialsProvider.lookupStores(folder)') -or
    -not $portfolioCredentialHelpers.Contains('candidate.getContext()?.is(folder)') -or
    -not $portfolioCredentialHelpers.Contains("folder.getFullName() != 'portfolio-dispatch'") -or
    -not $portfolioCredentialHelpers.Contains("'portfolio-dispatch/portfolio-pr-gate'") -or
    -not $portfolioCredentialHelpers.Contains("'portfolio-dispatch/portfolio-checkout-credential-reaper'") -or
    -not $portfolioCredentialHelpers.Contains('store.save()') -or
    $portfolioCredentialHelpers.Contains('SystemCredentialsProvider') -or
    $portfolioPipeline.Contains('SystemCredentialsProvider') -or
    -not $portfolioReaperPipeline.Contains('portfolioCleanupStaleCheckoutCredentials(currentBuild.rawBuild, 65 * 60 * 1000L)') -or
    -not $jobs.Contains('portfolioCredentialStoreHelpers.isEmpty()') -or
    -not $jobs.Contains('portfolioPipelineTemplate.count(portfolioCredentialStoreMarker) != 1') -or
    -not $jobs.Contains('portfolioReaperPipelineTemplate.count(portfolioCredentialStoreMarker) != 1') -or
    -not $jobs.Contains('portfolioReaperPipelineTemplate = portfolioReaperPipelineTemplate.replace(')) {
    throw 'Temporary checkout credentials must stay in the dedicated folder credential store, roll back on registration failures, and be reaped independently of manual dispatch.'
}
if (-not $groovySyntaxVerifier.Contains("'casc/pipelines/portfolio-credential-store.groovy'") -or
    -not $groovySyntaxVerifier.Contains("'casc/pipelines/portfolio-checkout-credential-reaper.groovy'")) {
    throw 'Jenkins-pinned Groovy syntax validation must parse the shared portfolio credential helper and its reaper Pipeline.'
}
foreach ($forbiddenPublicPortfolioOutput in @(
    'Catalog file blob:',
    'Jenkins run:',
    'summary: "Centrally trusted profile ${profileId}',
    '${catalogBlobSha}',
    '${jenkinsUrl}'
)) {
    if ($portfolioPipeline.Contains($forbiddenPublicPortfolioOutput)) {
        throw "The GitHub-visible portfolio check output must not disclose private implementation metadata: $forbiddenPublicPortfolioOutput"
    }
}
if (-not $jobs.Contains("def portfolioCatalogRepository = System.getenv('JENKINS_PORTFOLIO_CATALOG_REPOSITORY')?.trim()") -or
    -not $jobs.Contains('def portfolioCatalogEnabled = !portfolioCatalogRepository.isEmpty()') -or
    -not $jobs.Contains('disabled(!portfolioCatalogEnabled)') -or
    -not $jobs.Contains("JsonOutput.toJson(portfolioCatalogRepository)") -or
    -not $jobs.Contains('portfolioPipelineTemplate.count(portfolioCatalogRepositoryMarker) != 1') -or
    -not $environmentExample.Contains('JENKINS_PORTFOLIO_CATALOG_REPOSITORY=') -or
    -not $compose.Contains('JENKINS_PORTFOLIO_CATALOG_REPOSITORY: ${JENKINS_PORTFOLIO_CATALOG_REPOSITORY:-}')) {
    throw 'The private catalog location must be optional, injected through ignored local configuration, and JSON-encoded into the trusted Pipeline.'
}
if (-not $groovySyntaxVerifier.Contains("'casc/pipelines/portfolio-pr-poller.groovy'") -or
    -not $groovySyntaxFixture.Contains("'portfolio-pr-poller.groovy': [") -or
    -not $groovySyntaxFixture.Contains("'/* JENKINS_PORTFOLIO_NODE_BINARY */': '/usr/bin/node'") -or
    -not $portfolioPollerPipeline.Contains('agent none') -or
    -not $portfolioPollerPipeline.Contains('skipDefaultCheckout(true)') -or
    -not $portfolioPollerPipeline.Contains('portfolioPollDrain(') -or
    -not $portfolioPollerPipeline.Contains('Map portfolioPollPlan(def run, String nodeBinary, String adapterPath, Map envelope)') -or
    -not $portfolioPollerPipeline.Contains('portfolioPollCheckObservation(') -or
    -not $portfolioPollerPipeline.Contains('portfolioPollBuildCorrelation(') -or
    -not $portfolioPollerPipeline.Contains('[checks: org.kohsuke.github.GHPermissionType.READ]') -or
    -not $portfolioPollerPipeline.Contains('[checks: org.kohsuke.github.GHPermissionType.WRITE]') -or
    -not $portfolioPollerPipeline.Contains('check_name=jenkins-pr-gate&app_id=${expectedAppId}&filter=all') -or
    -not $portfolioPollerPipeline.Contains('runResult?.app?.id?.toString() == expectedAppId') -or
    -not $portfolioPollerPipeline.Contains('portfolioPollHasExpectedBuildIdentity(') -or
    -not $portfolioPollerPipeline.Contains('portfolioPollRecoverOrphanedCheck(') -or
    -not $portfolioPollerPipeline.Contains('observationTime - dispatchedAt >= 15 * 60 * 1000L') -or
    -not $portfolioPollerPipeline.Contains('String dispatchId = java.util.UUID.randomUUID().toString()') -or
    -not $portfolioPollerPipeline.Contains('selectedState.dispatchId = dispatchId') -or
    -not $portfolioPollerPipeline.Contains('string(name: ''PORTFOLIO_DISPATCH_ID'', value: dispatchId)') -or
    -not $portfolioPollerPipeline.Contains('matching.size() != 1') -or
    -not $portfolioPollerPipeline.Contains('exactCheck.output?.title == ''Jenkins run disappeared; recovery will retry''') -or
    $portfolioPollerPipeline.Contains('updated_at') -or
    $portfolioPollerPipeline.Contains('created_at') -or
    -not $portfolioPollerPipeline.Contains("status: observedStatus") -or
    -not $portfolioPollerPipeline.Contains('The Jenkins build linked to this check is no longer queued or running.') -or
    -not $portfolioPollerPipeline.Contains('portfolioPollWriteState(state)') -or
    -not $portfolioPollerPipeline.Contains('Persist its attempt intent before') -or
    -not $portfolioPollerPipeline.Contains('other eligible PRs are not counted as attempted') -or
    -not $portfolioPipeline.Contains('String portfolioDispatchIdForRun(def run)') -or
    -not $portfolioPipeline.Contains("upstreamCause?.getUpstreamProject() != 'portfolio-dispatch/portfolio-pr-poller'") -or
    -not $portfolioPipeline.Contains('external_id: externalId') -or
    -not $portfolioPollerPipeline.Contains('readers.submit(') -or
    -not $portfolioPollerPipeline.Contains('waitFor(30, java.util.concurrent.TimeUnit.SECONDS)') -or
    -not $portfolioPollerPipeline.Contains('String token = portfolioPollScopedAppToken(') -or
    $portfolioPollerPipeline.Contains('portfolioPollRepoApiRequest(') -or
    -not $portfolioPollerPipeline.Contains('[pull_requests: org.kohsuke.github.GHPermissionType.READ]') -or
    -not $portfolioPollerPipeline.Contains('[contents: org.kohsuke.github.GHPermissionType.READ]') -or
    -not $portfolioPollerPipeline.Contains('targetPlan.repositories.size() > 40') -or
    -not $portfolioPollerPipeline.Contains('portfolioPollGateBusy()') -or
    # Queue items are not all Jobs: a Pipeline node step waiting for an executor is a
    # PlaceholderTask with no getFullName(), and asking it unguarded fails the whole poll
    # whenever any other build waits for an agent.
    $portfolioPollerPipeline.Contains('item.task?.getFullName()') -or
    -not $portfolioPollerPipeline.Contains('item.task instanceof hudson.model.Job') -or
    -not $portfolioPollerPipeline.Contains("job: 'portfolio-dispatch/portfolio-pr-gate'") -or
    -not $portfolioPollerPipeline.Contains('wait: false') -or
    -not $portfolioPollerPipeline.Contains('portfolioPollWriteState(state)') -or
    $portfolioPollerPipeline.Contains('checkout scm') -or
    $portfolioPollerPipeline.Contains('withCredentials(') -or
    -not $jobs.Contains('disabled(!portfolioCatalogEnabled || !portfolioPrPollingEnabled)') -or
    -not $jobs.Contains("cron('H/5 * * * *')") -or
    -not $jobs.Contains('portfolioPollerMarkers.each') -or
    -not $compose.Contains('JENKINS_PORTFOLIO_PR_POLL_ENABLED: ${JENKINS_PORTFOLIO_PR_POLL_ENABLED:-false}') -or
    -not $environmentExample.Contains('JENKINS_PORTFOLIO_PR_POLL_ENABLED=false') -or
    -not $pilotConfigParser.Contains("'JENKINS_PORTFOLIO_PR_POLL_ENABLED'") -or
    -not $pilotConfigParser.Contains('PortfolioPrPollingEnabled = [bool]::Parse($portfolioPrPollingEnabled)') -or
    -not $portfolioPollerCli.Contains("input?.mode === 'targets'") -or
    -not $portfolioPollerCli.Contains('planRoutinePullRequestPoll(') -or
    -not $portfolioPollerCli.Contains('checkObservations') -or
    -not $portfolioConsumer.Contains('const POLL_RETRY_AFTER_MS = 15 * 60 * 1000') -or
    -not $portfolioConsumer.Contains('const POLL_MAX_ATTEMPTS = 3') -or
    -not $portfolioConsumer.Contains("['pending', 'completed', 'stalled']") -or
    -not $portfolioConsumer.Contains('ROUTINE_DISPATCH_PROFILE_PAIRS.some((pair) =>') -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-test-platform'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-blender-api'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-cloudflare-api'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-fmod-api'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-game-maker'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-github-api'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-game-platform-sdk'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/Game-Planetary-Survey'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/game-fraction-match'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/curiouspathway'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-portfolio-graph'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-jira-api'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-vercel-api'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-jenkins'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-setness-consulting'") -or
    -not $portfolioConsumer.Contains("'setnessconsulting/project-game-maker'") -or
    -not $portfolioConsumer.Contains("'project-game-maker-python312'") -or
    -not $portfolioConsumer.Contains("additionalPythonVersion: '3.11.17'") -or
    -not $portfolioConsumer.Contains("'setness-web-ci-node22-v1'") -or
    -not $portfolioConsumer.Contains("'python312-blender-api-v1'") -or
    -not $portfolioConsumer.Contains("'python312-cloudflare-api-uv-v1'") -or
    -not $portfolioConsumer.Contains("'python312-fmod-api-v1'") -or
    -not $portfolioConsumer.Contains("'python312-game-maker-v1'") -or
    -not $portfolioConsumer.Contains("'jenkins-repository-contract'") -or
    -not $portfolioConsumer.Contains("'node2214-vercel-api-gitleaks-v1'") -or
    -not $portfolioConsumer.Contains("'node22-verify-clean-checkout-v1'") -or
    -not $portfolioConsumer.Contains("'node24-game-planetary-survey-v1'") -or
    -not $portfolioConsumer.Contains("'node24-game-fraction-match-full-ci-v1'") -or
    -not $portfolioConsumer.Contains("setnessconsulting/game-fraction-match") -or
    -not $portfolioConsumer.Contains("['missing', 'in_progress', 'orphaned', 'untracked', 'completed']") -or
    -not $portfolioConsumer.Contains("'dispatchId'") -or
    -not $portfolioConsumer.Contains('const dispatches = dispatchCandidates.slice(0, 1)') -or
    -not $portfolioConsumer.Contains('nextState.set(key, previous)') -or
    -not $portfolioPollerTests.Contains('a missing check waits through the grace period before a bounded retry') -or
    -not $portfolioPollerTests.Contains('an orphaned in-progress check waits through the grace period before recovery') -or
    -not $portfolioPollerTests.Contains('an in-progress check not linked to this poller is never overwritten or retried') -or
    -not $portfolioPollerTests.Contains('multiple eligible PRs queue one at a time and only the selected PR advances state') -or
    -not $portfolioPipeline.Contains('portfolio-dispatch:${dispatchId.toLowerCase()}') -or
    -not $jobs.Contains("stringParam('PORTFOLIO_DISPATCH_ID'") -or
    -not $portfolioPollerTests.Contains('a missing exact-SHA check is stalled after the bounded retry budget') -or
    -not $portfolioPollerTests.Contains('polling is inert until the private control plane is explicitly active') -or
    -not $portfolioPollerTests.Contains('only centrally approved implementations are polled') -or
    -not $portfolioPollerTests.Contains('Fraction Match full CI polling binds to its exact shadow profile and repository') -or
    -not $portfolioConsumerTests.Contains('resolves both Game Maker Python matrix legs on its exact existing profile and repository') -or
    -not $portfolioPollerTests.Contains('project Jenkins self-check dispatches only the owner same-repository shadow head') -or
    -not $portfolioPollerTests.Contains('project Jenkins self-check rejects fork, outside-author, draft, closed, mismatched-base, and planned cases') -or
    -not $portfolioPollerTests.Contains('routine polling stays within the explicit sixteen-repository portfolio-dispatch allowlist') -or
    -not $portfolioPollerCliTests.Contains('planner fails closed on malformed input, oversized data, and caller arguments') -or
    -not $portfolioAdapterDocs.Contains('JENKINS_PORTFOLIO_PR_POLL_ENABLED=true') -or
    -not $portfolioAdapterDocs.Contains('queues one') -or
    -not $portfolioConsumerDocs.Contains('controlPlane.status: active')) {
    throw 'The opt-in portfolio poller must remain controller-only, bounded, least-permission, centrally allowlisted, and disabled by default.'
}
if (-not $portfolioConsumerDocs.Contains('python312-game-maker-v1') -or
    -not $portfolioConsumerDocs.Contains('Python 3.11.17') -or
    -not $portfolioConsumerDocs.Contains('Python 3.12.14') -or
    -not $portfolioConsumerDocs.Contains('`setup-python`') -or
    -not $portfolioConsumerDocs.Contains('floating `3.11` patch') -or
    -not $portfolioConsumerDocs.Contains('Actions remains authoritative')) {
    throw 'The Game Maker matrix shadow documentation must name both pinned runtimes and retain the Actions authority boundary.'
}
if (-not $portfolioConsumer.Contains('const PROFILE_KEYS = new Set([') -or
    $portfolioConsumer.Contains('export function resolveShadowExecution(catalog, profileId, headSha)') -or
    -not $portfolioConsumer.Contains("if (!allowed.has(key)) reject('unexpected-field'") -or
    -not $portfolioConsumerTests.Contains('rejects profile fields that could inject commands or credentials') -or
    -not $portfolioConsumerTests.Contains('accepts only exact, open, same-repository PR heads from allowlisted authors') -or
    -not $portfolioConsumerTests.Contains('returns executable commands only after PR identity and profile repository bind') -or
    -not $portfolioConsumerTests.Contains('rejects a profile whose required Node.js runtime differs from the pinned agent') -or
    -not $portfolioConsumerTests.Contains('resolves the centrally pinned Node 24 lint, type, and test implementation') -or
    -not $portfolioConsumerTests.Contains('resolves the exact Fraction Match full CI profile and ordered browser lane') -or
    -not $portfolioConsumerTests.Contains('resolves the project-jenkins self-check on the no-socket Node 22.23 agent') -or
    -not $portfolioConsumerTests.Contains('resolves the clean-checkout workflow on the isolated Node 22.14 disposable agent') -or
    -not $portfolioConsumerTests.Contains('resolves Vercel API secret-scan and tests on the isolated Node 22.14 Gitleaks agent') -or
    -not $portfolioConsumerTests.Contains('resolves Unity API maintenance on the isolated Node 22.14 disposable agent') -or
    -not $portfolioConsumerTests.Contains('implementation-repository-mismatch') -or
    -not $portfolioConsumerTests.Contains('resolves the GitHub API foundation on the no-socket Node 22.23 profile') -or
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
    $node2214Dockerfile.Contains('integration/portfolio-profile-contract') -or
    $node24Dockerfile.Contains('integration/portfolio-profile-contract') -or
    $playwrightDockerfile.Contains('integration/portfolio-profile-contract') -or
    $secondaryPlaywrightDockerfile.Contains('integration/portfolio-profile-contract') -or
    -not $portfolioConsumerPackage.Contains('"node": ">=22.23.3"') -or
    $portfolioPipeline.Contains('withCredentials(') -or
    $portfolioPipeline.Contains('env.PORTFOLIO_CHECKOUT_TOKEN') -or
    $portfolioConsumerDocs -match 'not yet wired into\s+a live Jenkins job' -or
    -not $portfolioAdapterDocs.Contains('manual shadow dispatcher') -or
    -not $portfolioAdapterDocs.Contains('one-repository App tokens') -or
    -not $portfolioAdapterDocs.Contains('refreshes the PR again after an agent becomes available') -or
    -not $portfolioAdapterDocs.Contains('controller image') -or
    -not $portfolioAdapterDocs.Contains('agent images do not include it') -or
    -not $portfolioConsumerDocs.Contains('Fork PRs are rejected')) {
    throw 'The portfolio resolver must remain data-only and the manual controller dispatcher must preserve per-repository token, exact-SHA, no-target-Pipeline, and cleanup boundaries.'
}

Write-Output 'Compose isolation, disposable Node 22/Node 22.14/Node 24/Python 3.12/Playwright agents, controller-before-checkout authorization, opt-in secondary-repository profile, separate verification lanes, credential boundaries, check reporting, recovery gates, trusted-pipeline contracts, Test Platform consumer contract, and disabled-by-default repository-scoped portfolio poller/dispatcher contracts passed.'
