import groovy.json.JsonOutput

def targetOwner = System.getenv('JENKINS_TARGET_REPO_OWNER')?.trim()
def targetRepository = System.getenv('JENKINS_TARGET_REPO_NAME')?.trim()
def jobName = System.getenv('JENKINS_MULTIBRANCH_JOB_NAME')?.trim()
def markerFile = System.getenv('JENKINS_MARKER_FILE')?.trim()
def candidatePathRules = (System.getenv('JENKINS_CANDIDATE_PATHS') ?: '')
    .split(',')
    .collect { it.trim() }
    .findAll { !it.isEmpty() }

if (!(targetOwner ==~ /[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/) ||
        !(targetRepository ==~ /[A-Za-z0-9._-]{1,100}/) ||
        !(jobName ==~ /[A-Za-z0-9._-]{1,100}/) ||
        !(markerFile ==~ /[A-Za-z0-9._\/-]+/) || markerFile.startsWith('/') ||
        markerFile.split('/').any { segment -> segment == '.' || segment == '..' }) {
    throw new IllegalStateException('Set valid local target repository and multibranch job values in the ignored .env file.')
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
def trustedAuthorsMarker = '/* JENKINS_PILOT_TRUSTED_PR_AUTHORS */'
if (trustedPipeline.count(trustedAuthorsMarker) != 1) {
    throw new IllegalStateException('The trusted Pipeline template has a missing or duplicate owner allowlist marker.')
}
trustedPipeline = trustedPipeline.replace(trustedAuthorsMarker, JsonOutput.toJson([targetOwner]))

multibranchPipelineJob(jobName) {
    displayName('Repository CI gate (shadow)')
    description('''
        Shadow-mode Jenkins pilot for the locally configured repository.
        The current Actions requirements remain authoritative until the Epic GO gate.
    '''.stripIndent().trim())

    branchSources {
        github {
            id('jenkins-pilot-source')
            scanCredentialsId('setness-jenkins-app')
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
        Node sshCheckout = sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.SSHCheckoutTrait')
        sshCheckout.appendNode('credentialsId', 'setness-jenkins-readonly-checkout')

        Node branchFilter = sourceTraits.appendNode('jenkins.scm.impl.trait.WildcardSCMHeadFilterTrait')
        branchFilter.appendNode('includes', 'main PR-*')
        branchFilter.appendNode('excludes', '')

        Node branchDiscovery = sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait')
        branchDiscovery.appendNode('strategyId', '1')

        Node pullRequestDiscovery = sourceTraits.appendNode('org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait')
        pullRequestDiscovery.appendNode('strategyId', '1')

        // Suppress the Checks plugin's automatic lifecycle publisher so it
        // cannot overwrite the reviewer summary from the trusted Pipeline.
        Node gateChecks = sourceTraits.appendNode('io.jenkins.plugins.checks.github.status.GitHubSCMSourceStatusChecksTrait')
        gateChecks.appendNode('name', 'jenkins-pr-gate')
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
        inlineFactory.appendNode('sandbox', 'true')
    }
}
