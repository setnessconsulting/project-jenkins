import groovy.json.JsonOutput

def targetOwner = System.getenv('JENKINS_TARGET_REPO_OWNER')?.trim()
def targetRepository = System.getenv('JENKINS_TARGET_REPO_NAME')?.trim()
def jobName = System.getenv('JENKINS_MULTIBRANCH_JOB_NAME')?.trim()
def markerFile = System.getenv('JENKINS_MARKER_FILE')?.trim()
def primaryCheckName = System.getenv('JENKINS_PRIMARY_CHECK_NAME')?.trim()
def candidateCheckName = System.getenv('JENKINS_CANDIDATE_CHECK_NAME')?.trim()
def appDirectory = System.getenv('JENKINS_APP_DIRECTORY')?.trim()
def tutorWebDirectory = System.getenv('JENKINS_TUTOR_WEB_DIRECTORY')?.trim()
def e2eJobName = System.getenv('JENKINS_E2E_JOB_NAME')?.trim()
def e2eScheduleEnabledValue = (System.getenv('JENKINS_E2E_SCHEDULE_ENABLED') ?: 'false').trim().toLowerCase()
def siteUrl = System.getenv('JENKINS_SITE_URL')?.trim()
def githubAppId = System.getenv('JENKINS_GITHUB_APP_ID')?.trim()
def appCredentialId = System.getenv('JENKINS_GITHUB_APP_CREDENTIAL_ID')?.trim()
def checkoutCredentialId = System.getenv('JENKINS_CHECKOUT_SSH_CREDENTIAL_ID')?.trim() ?: 'jenkins-readonly-checkout'
def candidatePathRules = (System.getenv('JENKINS_CANDIDATE_PATHS') ?: '')
    .split(',')
    .collect { it.trim() }
    .findAll { !it.isEmpty() }

if (!(e2eScheduleEnabledValue in ['true', 'false'])) {
    throw new IllegalStateException('JENKINS_E2E_SCHEDULE_ENABLED must be true or false.')
}
def e2eScheduleEnabled = e2eScheduleEnabledValue == 'true'

if (!(targetOwner ==~ /[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/) ||
        !(targetRepository ==~ /[A-Za-z0-9._-]{1,100}/) ||
        !(jobName ==~ /[A-Za-z0-9._-]{1,100}/) ||
        !(markerFile ==~ /[A-Za-z0-9._\/-]+/) || markerFile.startsWith('/') ||
        markerFile.split('/').any { segment -> segment == '.' || segment == '..' }) {
    throw new IllegalStateException('Set valid local target repository and multibranch job values in the ignored .env file.')
}
if (!(primaryCheckName ==~ /[A-Za-z0-9][A-Za-z0-9 ._-]{0,99}/) ||
        !(candidateCheckName ==~ /[A-Za-z0-9][A-Za-z0-9 ._-]{0,99}/) ||
        !(appCredentialId ==~ /[A-Za-z0-9._-]{1,100}/) ||
        !(githubAppId ==~ /[0-9]{1,20}/) ||
        !(checkoutCredentialId ==~ /[A-Za-z0-9._-]{1,100}/) ||
        !(appDirectory ==~ /[A-Za-z0-9._\/-]+/) || appDirectory.startsWith('/') ||
        appDirectory.split('/').any { segment -> segment == '.' || segment == '..' } ||
        !(tutorWebDirectory ==~ /[A-Za-z0-9._\/-]+/) || tutorWebDirectory.startsWith('/') ||
        tutorWebDirectory.split('/').any { segment -> segment == '.' || segment == '..' } ||
        !(e2eJobName ==~ /[A-Za-z0-9._-]{1,100}/) || e2eJobName == jobName ||
        !siteUrl?.startsWith('https://') || siteUrl.contains('@') || siteUrl.contains(' ')) {
    throw new IllegalStateException('Set valid private check names, relative application directories, a separate E2E job name, and HTTPS site URL in the ignored local .env file.')
}
if (candidatePathRules.isEmpty() || candidatePathRules.any { rule ->
        !(rule ==~ /[A-Za-z0-9._\/-]+/) || rule.startsWith('/') ||
            rule.split('/').any { segment -> segment == '.' || segment == '..' }
    } || candidatePathRules.unique().size() != candidatePathRules.size()) {
    throw new IllegalStateException('Set valid, unique relative candidate path rules in the ignored .env file.')
}

def pipelineTemplate = new File(
    '/usr/share/jenkins/casc/pipelines/repository-pilot.groovy'
).getText('UTF-8')
def candidateRulesMarker = '/* JENKINS_PILOT_CANDIDATE_PATH_RULES */'
if (pipelineTemplate.count(candidateRulesMarker) != 1) {
    throw new IllegalStateException('The trusted Pipeline template has a missing or duplicate candidate-rule marker.')
}
def trustedPipeline = pipelineTemplate.replace(candidateRulesMarker, JsonOutput.toJson(candidatePathRules))
[
    '/* JENKINS_PILOT_PRIMARY_CHECK_NAME */': primaryCheckName,
    '/* JENKINS_PILOT_CANDIDATE_CHECK_NAME */': candidateCheckName,
    '/* JENKINS_PILOT_APP_DIRECTORY */': appDirectory,
    '/* JENKINS_PILOT_TUTOR_WEB_DIRECTORY */': tutorWebDirectory,
    '/* JENKINS_PILOT_SITE_URL */': siteUrl
].each { marker, value ->
    if (trustedPipeline.count(marker) != 1) {
        throw new IllegalStateException('The trusted Pipeline template has a missing or duplicate local configuration marker.')
    }
    trustedPipeline = trustedPipeline.replace(marker, JsonOutput.toJson(value))
}
def trustedAuthorsMarker = '/* JENKINS_PILOT_TRUSTED_PR_AUTHORS */'
if (trustedPipeline.count(trustedAuthorsMarker) != 1) {
    throw new IllegalStateException('The trusted Pipeline template has a missing or duplicate owner allowlist marker.')
}
trustedPipeline = trustedPipeline.replace(trustedAuthorsMarker, JsonOutput.toJson([targetOwner]))

def e2ePipelineTemplate = new File(
    '/usr/share/jenkins/casc/pipelines/e2e.groovy'
).getText('UTF-8')
[
    '/* JENKINS_PILOT_E2E_REPOSITORY */': "git@github.com:${targetOwner}/${targetRepository}.git",
    '/* JENKINS_PILOT_E2E_DETAILS_BASE */': "https://github.com/${targetOwner}/${targetRepository}/commit/",
    '/* JENKINS_PILOT_E2E_CHECKOUT_CREDENTIAL_ID */': checkoutCredentialId,
    '/* JENKINS_PILOT_E2E_APP_CREDENTIAL_ID */': appCredentialId,
    // Encode once in the shared replace below. Pre-encoding these values
    // would double-quote App ID / owner / repository and break App+SHA checks.
    '/* JENKINS_PILOT_E2E_APP_ID */': githubAppId,
    '/* JENKINS_PILOT_E2E_REPOSITORY_OWNER */': targetOwner,
    '/* JENKINS_PILOT_E2E_REPOSITORY_NAME */': targetRepository,
    '/* JENKINS_PILOT_E2E_APP_DIRECTORY */': appDirectory
].each { marker, value ->
    if (e2ePipelineTemplate.count(marker) != 1) {
        throw new IllegalStateException('The centrally trusted E2E Pipeline template has a missing or duplicate local configuration marker.')
    }
    e2ePipelineTemplate = e2ePipelineTemplate.replace(marker, JsonOutput.toJson(value))
}

def testPlatformJobName = System.getenv('JENKINS_TEST_PLATFORM_JOB_NAME')?.trim()
def testPlatformNodeBinary = System.getenv('JENKINS_TEST_PLATFORM_NODE')?.trim()
def testPlatformAdapterRoot = System.getenv('JENKINS_TEST_PLATFORM_ADAPTER_ROOT')?.trim()
def testPlatformEvidenceRoot = (System.getenv('JENKINS_TEST_PLATFORM_EVIDENCE_ROOT')?.trim()) ?: ''
if (!(testPlatformJobName ==~ /[A-Za-z0-9._-]{1,100}/) ||
        !(testPlatformNodeBinary ==~ /[A-Za-z0-9._\/-]{1,200}/) ||
        !(testPlatformAdapterRoot ==~ /[A-Za-z0-9._\/-]{1,200}/) || !testPlatformAdapterRoot.startsWith('/') ||
        testPlatformAdapterRoot.split('/').any { segment -> segment == '.' || segment == '..' } ||
        (!testPlatformEvidenceRoot.isEmpty() &&
            ((!(testPlatformEvidenceRoot ==~ /[A-Za-z0-9._\/-]{1,200}/) || !testPlatformEvidenceRoot.startsWith('/') ||
                testPlatformEvidenceRoot.split('/').any { segment -> segment == '.' || segment == '..' })))) {
    throw new IllegalStateException('Set a valid Test Platform job name, controller node binary, and absolute adapter/evidence roots in the ignored .env file.')
}

def testPlatformPipelineTemplate = new File(
    '/usr/share/jenkins/casc/pipelines/test-platform.groovy'
).getText('UTF-8')

// The second repository is a separately enabled profile. Its repo-scoped
// checkout key and trusted author allowlist must be configured explicitly;
// no discovery or checkout occurs while this profile remains disabled.
def secondaryEnabledValue = (System.getenv('JENKINS_SECONDARY_REPO_ENABLED') ?: 'false').trim().toLowerCase()
if (!(secondaryEnabledValue in ['true', 'false'])) {
    throw new IllegalStateException('JENKINS_SECONDARY_REPO_ENABLED must be true or false.')
}
def secondaryEnabled = secondaryEnabledValue == 'true'
def secondaryOwner = System.getenv('JENKINS_SECONDARY_REPO_OWNER')?.trim()
def secondaryRepository = System.getenv('JENKINS_SECONDARY_REPO_NAME')?.trim()
def secondaryJobName = System.getenv('JENKINS_SECONDARY_JOB_NAME')?.trim()
def secondaryCheckoutCredentialId = System.getenv('JENKINS_SECONDARY_CHECKOUT_CREDENTIAL_ID')?.trim()
def secondaryTrustedAuthors = (System.getenv('JENKINS_SECONDARY_TRUSTED_PR_AUTHORS') ?: '')
    .split(',')
    .collect { it.trim() }
    .findAll { !it.isEmpty() }
def secondaryPrimaryCheckName = System.getenv('JENKINS_SECONDARY_PRIMARY_CHECK_NAME')?.trim()
def secondarySmokeCheckName = System.getenv('JENKINS_SECONDARY_SMOKE_CHECK_NAME')?.trim()
def secondarySmokeUrl = (System.getenv('JENKINS_SECONDARY_SMOKE_URL') ?: '').trim()
def secondaryPipelineTemplate = null

if (secondaryEnabled) {
    if (!(secondaryOwner ==~ /[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/) ||
        !(secondaryRepository ==~ /[A-Za-z0-9._-]{1,100}/) ||
        (secondaryOwner.equalsIgnoreCase(targetOwner) && secondaryRepository.equalsIgnoreCase(targetRepository)) ||
        !(secondaryJobName ==~ /[A-Za-z0-9._-]{1,100}/) ||
        secondaryJobName in [jobName, e2eJobName, testPlatformJobName] ||
        !(secondaryCheckoutCredentialId ==~ /[A-Za-z0-9._-]{1,100}/) ||
        secondaryCheckoutCredentialId == checkoutCredentialId || secondaryCheckoutCredentialId == appCredentialId ||
        !(secondaryPrimaryCheckName ==~ /[A-Za-z0-9][A-Za-z0-9 ._-]{0,99}/) ||
        !(secondarySmokeCheckName ==~ /[A-Za-z0-9][A-Za-z0-9 ._-]{0,99}/) ||
        secondarySmokeCheckName == secondaryPrimaryCheckName ||
        secondaryTrustedAuthors.isEmpty() || secondaryTrustedAuthors.any { author ->
            !(author ==~ /[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/)
        } || secondaryTrustedAuthors.unique().size() != secondaryTrustedAuthors.size()) {
        throw new IllegalStateException('The enabled secondary repository requires valid repository/job/check values, a distinct read-only checkout credential, and an explicit unique PR-author allowlist.')
    }
    if (!secondarySmokeUrl.isEmpty()) {
        try {
            def smokeUri = new URI(secondarySmokeUrl)
            if (smokeUri.getScheme() != 'https' || !smokeUri.getHost() || smokeUri.getUserInfo() != null || secondarySmokeUrl.contains(' ')) {
                throw new IllegalArgumentException('invalid HTTPS smoke endpoint')
            }
        } catch (Exception ignored) {
            throw new IllegalStateException('The configured secondary smoke URL must be an owner-reviewed HTTPS URL without embedded credentials.')
        }
    }

    secondaryPipelineTemplate = new File(
        '/usr/share/jenkins/casc/pipelines/secondary-repository.groovy'
    ).getText('UTF-8')
    [
        '/* JENKINS_SECONDARY_OWNER */': secondaryOwner,
        '/* JENKINS_SECONDARY_REPOSITORY */': secondaryRepository,
        '/* JENKINS_SECONDARY_TRUSTED_AUTHORS */': secondaryTrustedAuthors,
        '/* JENKINS_SECONDARY_PRIMARY_CHECK_NAME */': secondaryPrimaryCheckName,
        '/* JENKINS_SECONDARY_SMOKE_CHECK_NAME */': secondarySmokeCheckName,
        '/* JENKINS_SECONDARY_SMOKE_URL */': secondarySmokeUrl
    ].each { marker, value ->
        if (secondaryPipelineTemplate.count(marker) != 1) {
            throw new IllegalStateException('The centrally trusted secondary-repository pipeline has a missing or duplicate configuration marker.')
        }
        secondaryPipelineTemplate = secondaryPipelineTemplate.replace(marker, JsonOutput.toJson(value))
    }
}

multibranchPipelineJob(jobName) {
    displayName('Repository CI gate (shadow)')
    description('''
        Shadow-mode Jenkins pilot for the locally configured repository.
        The current Actions requirements remain authoritative until the Epic GO gate.
    '''.stripIndent().trim())

    branchSources {
        github {
            id('jenkins-pilot-source')
            scanCredentialsId(appCredentialId)
            repoOwner(targetOwner)
            repository(targetRepository)
        }
    }

    triggers {
        periodicFolderTrigger {
            interval('5')
        }
    }

    orphanedItemStrategy {
        discardOldItems {
            daysToKeep(30)
            numToKeep(50)
        }
    }

    configure { Node project ->
        // Current Job DSL GitHub branch-source support does not expose the
        // SCM trait context natively, so encode its public plugin XML model.
        Node githubSource = project.depthFirst().find { element ->
            element instanceof Node &&
                element.name() == 'source' &&
                element.attributes()['class'] == 'org.jenkinsci.plugins.github_branch_source.GitHubSCMSource'
        } as Node
        if (githubSource == null) {
            throw new IllegalStateException('Job DSL did not create the configured GitHub SCM source.')
        }

        Node legacyCheckoutCredentials = githubSource.children().find { element ->
            element instanceof Node && element.name() == 'checkoutCredentialsId'
        } as Node
        if (legacyCheckoutCredentials != null) {
            githubSource.remove(legacyCheckoutCredentials)
        }

        Node oldTraits = githubSource.children().find { element ->
            element instanceof Node && element.name() == 'traits'
        } as Node
        if (oldTraits != null) {
            githubSource.remove(oldTraits)
        }
        Node sourceTraits = githubSource.appendNode('traits')
        Node branchFilter = sourceTraits.appendNode('jenkins.scm.impl.trait.WildcardSCMHeadFilterTrait')
        branchFilter.appendNode('includes', 'main PR-*')
        branchFilter.appendNode('excludes', '')

        Node branchDiscovery = sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait')
        branchDiscovery.appendNode('strategyId', '1')

        Node pullRequestDiscovery = sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait')
        pullRequestDiscovery.appendNode('strategyId', '1')

        // Use a separate repository-scoped read-only deploy key for agent
        // checkout. Branch Source scan credentials are trusted and can carry
        // the App's Checks-write permission.
        Node sshCheckout = sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.SSHCheckoutTrait')
        sshCheckout.appendNode('credentialsId', checkoutCredentialId)

        // The trusted Pipeline publishes both pending and final output with
        // reviewer-readable summaries. A missing check on a parse failure
        // remains fail-closed because GitHub cannot satisfy the required gate.
        Node gateChecks = sourceTraits.appendNode('io.jenkins.plugins.checks.github.status.GitHubSCMSourceStatusChecksTrait')
        gateChecks.appendNode('name', primaryCheckName)
        gateChecks.appendNode('skip', 'true')
        gateChecks.appendNode('skipNotifications', 'true')

        Node checksSettings = sourceTraits.appendNode('io.jenkins.plugins.checks.github.config.GitHubSCMSourceChecksTrait')
        checksSettings.appendNode('verboseConsoleLog', 'false')

        // This is the branch-job factory (not the similarly named organization
        // folder factory). It is deliberately bound to this checked-in
        // controller configuration, never a Jenkinsfile in the target PR.
        Node oldFactory = project.factory ? project.factory[0] : null
        if (oldFactory != null) {
            project.remove(oldFactory)
        }

        Node inlineFactory = project.appendNode('factory', [
            'class': 'org.jenkinsci.plugins.inlinepipeline.InlineDefinitionBranchProjectFactory'
        ])
        inlineFactory.appendNode('markerFile', markerFile)
        inlineFactory.appendNode('script', trustedPipeline)
        // This centrally trusted Pipeline reads the Branch Source head SHA
        // before checkout so blocked PRs can receive a SHA-verified failure.
        // The target repository cannot supply or override this script.
        inlineFactory.appendNode('sandbox', 'false')
    }
}

if (secondaryEnabled) {
    multibranchPipelineJob(secondaryJobName) {
        displayName('Secondary repository CI gate (shadow)')
        description('''
            Opt-in secondary repository profile using a centrally trusted pipeline.
            Actions remains authoritative until that repository independently passes its qualification and cutover gates.
        '''.stripIndent().trim())
        branchSources {
            github {
                id('secondary-repository-source')
                scanCredentialsId(appCredentialId)
                repoOwner(secondaryOwner)
                repository(secondaryRepository)
            }
        }
        triggers {
            periodicFolderTrigger {
                interval('5')
            }
        }
        orphanedItemStrategy {
            discardOldItems {
                daysToKeep(30)
                numToKeep(50)
            }
        }
        configure { Node project ->
            Node githubSource = project.depthFirst().find { element ->
                element instanceof Node && element.name() == 'source' &&
                    element.attributes()['class'] == 'org.jenkinsci.plugins.github_branch_source.GitHubSCMSource'
            } as Node
            if (githubSource == null) {
                throw new IllegalStateException('Job DSL did not create the secondary GitHub SCM source.')
            }
            Node oldTraits = githubSource.children().find { element ->
                element instanceof Node && element.name() == 'traits'
            } as Node
            if (oldTraits != null) githubSource.remove(oldTraits)

            Node sourceTraits = githubSource.appendNode('traits')
            Node branchFilter = sourceTraits.appendNode('jenkins.scm.impl.trait.WildcardSCMHeadFilterTrait')
            branchFilter.appendNode('includes', 'main PR-*')
            branchFilter.appendNode('excludes', '')
            Node branchDiscovery = sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait')
            branchDiscovery.appendNode('strategyId', '1')
            Node pullRequestDiscovery = sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait')
            // Build GitHub's synthetic merge revision, but publish the result on the verified PR head SHA.
            pullRequestDiscovery.appendNode('strategyId', '1')
            Node sshCheckout = sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.SSHCheckoutTrait')
            sshCheckout.appendNode('credentialsId', secondaryCheckoutCredentialId)
            Node gateChecks = sourceTraits.appendNode('io.jenkins.plugins.checks.github.status.GitHubSCMSourceStatusChecksTrait')
            gateChecks.appendNode('name', secondaryPrimaryCheckName)
            gateChecks.appendNode('skip', 'true')
            gateChecks.appendNode('skipNotifications', 'true')
            Node checksSettings = sourceTraits.appendNode('io.jenkins.plugins.checks.github.config.GitHubSCMSourceChecksTrait')
            checksSettings.appendNode('verboseConsoleLog', 'false')

            Node oldFactory = project.factory ? project.factory[0] : null
            if (oldFactory != null) project.remove(oldFactory)
            Node inlineFactory = project.appendNode('factory', [
                'class': 'org.jenkinsci.plugins.inlinepipeline.InlineDefinitionBranchProjectFactory'
            ])
            inlineFactory.appendNode('markerFile', 'package.json')
            inlineFactory.appendNode('script', secondaryPipelineTemplate)
            inlineFactory.appendNode('sandbox', 'false')
        }
    }
}

pipelineJob(e2eJobName) {
    displayName('Playwright E2E (scheduled/manual)')
    description('''
        Centrally trusted scheduled and owner-triggered E2E verification.
        This job is separate from the PR merge gate and has no deployment credentials.
    '''.stripIndent().trim())
    logRotator {
        daysToKeep(30)
        numToKeep(50)
    }
    parameters {
        stringParam('TARGET_SHA', 'main', 'Use main for the nightly run or provide a full commit SHA for a manual run.')
    }
    if (e2eScheduleEnabled) {
        triggers {
            cron('37 6 * * *')
        }
    }
    definition {
        cps {
            script(e2ePipelineTemplate)
            sandbox(false)
        }
    }
}

// The Test Platform contract consumer is a manual, credential-free job. It
// has no target-repository SCM binding: the operator places a Test Platform
// execution request JSON in the controller workspace and starts the job. The
// trusted Pipeline authorizes the request on the controller before any
// checkout, so a target pull request can never supply controller-trusted
// Jenkins logic through this job.
pipelineJob(testPlatformJobName) {
    displayName('Test Platform execution contract')
    description('''
        Centrally trusted consumer of Test Platform ExecutionPlans (API-390).
        Manual trigger only. No target repository SCM binding and no credentials.
    '''.stripIndent().trim())
    logRotator {
        daysToKeep(30)
        numToKeep(50)
    }
    parameters {
        stringParam('TEST_PLATFORM_EXECUTION_REQUEST', 'execution-request.json', 'Path of the Test Platform execution request JSON in the controller workspace.')
        stringParam('TEST_PLATFORM_RESOLUTION_PATH', 'resolution.json', 'Path for the controller-verified resolution.')
        stringParam('TEST_PLATFORM_RESULTS_PATH', 'results.json', 'Path for the normalized executor results.')
        stringParam('TEST_PLATFORM_SUBMISSION_PATH', 'receipt-submission.json', 'Path for the normalized receipt submission.')
        stringParam('JENKINS_TEST_PLATFORM_NODE', testPlatformNodeBinary, 'Node binary that runs the trusted adapter.')
        stringParam('JENKINS_TEST_PLATFORM_ADAPTER_ROOT', testPlatformAdapterRoot, 'Controller path of the trusted adapter.')
        stringParam('TEST_PLATFORM_EVIDENCE_ROOT', testPlatformEvidenceRoot ?: '', 'Optional controller evidence publication root.')
        stringParam('JENKINS_CHECKOUT_SSH_CREDENTIAL_ID', checkoutCredentialId, 'Read-only checkout credential for the target repository.')
    }
    definition {
        cps {
            script(testPlatformPipelineTemplate)
            sandbox(false)
        }
    }
}
