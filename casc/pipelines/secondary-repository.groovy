Map verifiedSecondaryPullRequestRevision(def run, String expectedChangeId, String owner, String repository) {
    if (!(expectedChangeId ==~ /[0-9]+/)) return null
    def revisionAction = run.getAction(jenkins.scm.api.SCMRevisionAction.class)
    def revision = revisionAction?.getRevision()
    if (!(revision instanceof org.jenkinsci.plugins.github_branch_source.PullRequestSCMRevision)) return null
    def pullRequestHead = revision.getHead()
    if (!(pullRequestHead instanceof org.jenkinsci.plugins.github_branch_source.PullRequestSCMHead) ||
        pullRequestHead.getId() != expectedChangeId ||
        !owner.equalsIgnoreCase(pullRequestHead.getSourceOwner() ?: '') ||
        !repository.equalsIgnoreCase(pullRequestHead.getSourceRepo() ?: '')) return null
    def headSha = revision.getPullHash()
    def baseSha = revision.getBaseHash()
    if (headSha == null || !(headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/) ||
        baseSha == null || !(baseSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) return null
    return [headSha: headSha.toLowerCase(), baseSha: baseSha.toLowerCase()]
}

boolean secondaryCheckoutMatchesPrRevision(String checkedOutSha, String parentLine, String expectedHeadSha, String expectedBaseSha) {
    if (checkedOutSha == null || !(checkedOutSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) return false
    if (checkedOutSha.equalsIgnoreCase(expectedHeadSha)) return true
    if (parentLine == null || expectedHeadSha == null || expectedBaseSha == null) return false
    def commitAndParents = parentLine.trim().split(/\s+/)
    return commitAndParents.length == 3 &&
        commitAndParents[0].equalsIgnoreCase(checkedOutSha) &&
        commitAndParents[1].equalsIgnoreCase(expectedBaseSha) &&
        commitAndParents[2].equalsIgnoreCase(expectedHeadSha)
}

boolean isSecondaryAuthorAllowed(String author, List<String> allowedAuthors) {
    def normalized = author?.trim()
    return normalized != null && !normalized.isEmpty() &&
        allowedAuthors.any { allowed -> allowed.equalsIgnoreCase(normalized) }
}

String secondaryCheckDetailsUrl(String owner, String repository, String changeId, String sha) {
    if (!(owner ==~ /[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/) ||
        !(repository ==~ /[A-Za-z0-9._-]{1,100}/) ||
        !(sha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) return null
    if (changeId != null && changeId ==~ /[0-9]+/) {
        return "https://github.com/${owner}/${repository}/pull/${changeId}/checks"
    }
    return "https://github.com/${owner}/${repository}/commit/${sha}/checks"
}

String secondarySmokeConclusion(String result) {
    switch (result) {
        case 'SUCCESS': return 'SUCCESS'
        case 'FAILURE': return 'FAILURE'
        case 'CANCELED': return 'CANCELED'
        case 'NOT_CONFIGURED':
        case 'NOT_RUN': return 'NEUTRAL'
        default: return 'FAILURE'
    }
}

def targetOwner = /* JENKINS_SECONDARY_OWNER */
def targetRepository = /* JENKINS_SECONDARY_REPOSITORY */
def trustedAuthors = /* JENKINS_SECONDARY_TRUSTED_AUTHORS */
def primaryCheckName = /* JENKINS_SECONDARY_PRIMARY_CHECK_NAME */
def smokeCheckName = /* JENKINS_SECONDARY_SMOKE_CHECK_NAME */
def smokeUrl = /* JENKINS_SECONDARY_SMOKE_URL */

pipeline {
    agent none

    options {
        timeout(time: 120, unit: 'MINUTES')
        disableConcurrentBuilds(abortPrevious: true)
        skipDefaultCheckout(true)
    }

    environment {
        JENKINS_SECONDARY_AUTHORIZATION = 'NOT_A_PR'
        JENKINS_SECONDARY_PR_HEAD_SHA = ''
        JENKINS_SECONDARY_PR_BASE_SHA = ''
        JENKINS_SECONDARY_CHECKED_OUT_SHA = ''
        JENKINS_SECONDARY_CI_RESULT = 'NOT_RUN'
        JENKINS_SECONDARY_PLAYWRIGHT_RESULTS = ''
        JENKINS_SECONDARY_SMOKE_RESULT = 'NOT_RUN'
        JENKINS_SECONDARY_SMOKE_DETAIL = 'No smoke result was recorded.'
    }

    stages {
        stage('Authorize pull request') {
            steps {
                script {
                    def branchName = env.BRANCH_NAME ?: ''
                    def changeId = env.CHANGE_ID?.trim()
                    def isPullRequest = changeId != null || branchName.matches('PR-[0-9]+')
                    env.JENKINS_SECONDARY_SMOKE_RESULT = smokeUrl ? 'NOT_RUN' : 'NOT_CONFIGURED'
                    env.JENKINS_SECONDARY_SMOKE_DETAIL = smokeUrl
                        ? 'Read-only smoke is configured and will be reported separately.'
                        : 'Not configured: owner-reviewed smoke URL is absent; no live request was made.'

                    if (!isPullRequest) {
                        if (branchName == 'main') return
                        env.JENKINS_SECONDARY_AUTHORIZATION = 'DENIED'
                        env.JENKINS_SECONDARY_CI_RESULT = 'FAILURE'
                        env.JENKINS_SECONDARY_SMOKE_RESULT = 'NOT_RUN'
                        env.JENKINS_SECONDARY_SMOKE_DETAIL = 'Not run: only main and approved same-repository PRs are eligible.'
                        error('Secondary profile refuses non-main branch builds before checkout or repository commands.')
                    }
                    def verifiedRevision = verifiedSecondaryPullRequestRevision(
                        currentBuild.rawBuild, changeId, targetOwner, targetRepository
                    )
                    if (verifiedRevision == null) {
                        error('Could not verify this same-repository PR head SHA; no checkout or repository command was run.')
                    }
                    def verifiedSha = verifiedRevision.headSha
                    def detailsUrl = secondaryCheckDetailsUrl(targetOwner, targetRepository, changeId, verifiedSha)
                    if (detailsUrl == null) {
                        error('Could not construct a verified GitHub check URL; no checkout or repository command was run.')
                    }
                    env.JENKINS_SECONDARY_PR_HEAD_SHA = verifiedSha
                    env.JENKINS_SECONDARY_PR_BASE_SHA = verifiedRevision.baseSha

                    if (!isSecondaryAuthorAllowed(env.CHANGE_AUTHOR, trustedAuthors)) {
                        env.JENKINS_SECONDARY_AUTHORIZATION = 'DENIED'
                        env.JENKINS_SECONDARY_CI_RESULT = 'FAILURE'
                        env.JENKINS_SECONDARY_SMOKE_RESULT = 'NOT_RUN'
                        env.JENKINS_SECONDARY_SMOKE_DETAIL = 'Not run: this PR was blocked before checkout or repository commands.'
                        error('Owner-only secondary-repository shadow denied this PR before checkout.')
                    }

                    env.JENKINS_SECONDARY_AUTHORIZATION = 'AUTHORIZED'
                    publishChecks(
                        name: primaryCheckName,
                        title: 'Required CI check: RUNNING',
                        summary: 'Same-repository PR head verified; Node 24 CI and Playwright verification are starting.',
                        text: "PR #${changeId}\nVerified PR head SHA: ${verifiedSha}\nVerified PR base SHA: ${verifiedRevision.baseSha}\nAuthorization: ${env.CHANGE_AUTHOR}\nNo target Jenkinsfile is loaded.",
                        detailsURL: detailsUrl,
                        status: 'IN_PROGRESS'
                    )
                }
            }
        }

        stage('Trusted pipeline self-test') {
            steps {
                script {
                    assert isSecondaryAuthorAllowed(trustedAuthors[0], trustedAuthors)
                    assert !isSecondaryAuthorAllowed('unapproved-contributor', trustedAuthors)
                    assert !isSecondaryAuthorAllowed(null, trustedAuthors)
                    assert secondarySmokeConclusion('NOT_CONFIGURED') == 'NEUTRAL'
                    assert secondarySmokeConclusion('SUCCESS') == 'SUCCESS'
                    assert secondarySmokeConclusion('FAILURE') == 'FAILURE'
                    assert secondarySmokeConclusion('CANCELED') == 'CANCELED'
                    assert secondaryCheckoutMatchesPrRevision('a' * 40, null, 'a' * 40, 'b' * 40)
                    assert secondaryCheckoutMatchesPrRevision('c' * 40, "${'c' * 40} ${'b' * 40} ${'a' * 40}", 'a' * 40, 'b' * 40)
                    assert !secondaryCheckoutMatchesPrRevision('c' * 40, "${'c' * 40} ${'a' * 40} ${'b' * 40}", 'a' * 40, 'b' * 40)
                    assert secondaryCheckDetailsUrl(targetOwner, targetRepository, '17', 'a' * 40) ==
                        "https://github.com/${targetOwner}/${targetRepository}/pull/17/checks"
                    assert verifiedSecondaryPullRequestRevision(null, '17', targetOwner, targetRepository) == null
                    echo 'Secondary repository authorization, same-repository, SHA, and smoke-result policy self-tests passed.'
                }
            }
        }

        stage('Node 24 CI and Playwright') {
            agent {
                label 'secondary-node24-playwright-ephemeral'
            }
            steps {
                script {
                    deleteDir()
                    try {
                        checkout scm
                        def checkedOutSha = sh(returnStdout: true, script: 'git rev-parse HEAD').trim().toLowerCase()
                        if (!(checkedOutSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
                            error('Checkout did not produce a full commit SHA.')
                        }
                        if (env.CHANGE_ID) {
                            def parents = sh(returnStdout: true, script: 'git rev-list --parents -n 1 HEAD').trim()
                            if (!secondaryCheckoutMatchesPrRevision(
                                checkedOutSha,
                                parents,
                                env.JENKINS_SECONDARY_PR_HEAD_SHA,
                                env.JENKINS_SECONDARY_PR_BASE_SHA
                            )) {
                                error('Checkout is neither the verified PR head nor its merge with the verified base; no tests ran.')
                            }
                        }
                        env.JENKINS_SECONDARY_CHECKED_OUT_SHA = checkedOutSha
                        sh '''#!/usr/bin/env bash
set -euo pipefail
test "$(node --version)" = "v24.21.0"
node --version
npm --version
'''
                        sh 'npm ci --no-audit --no-fund'
                        sh 'npm run typecheck'
                        sh 'npm run lint'
                        sh 'npm run test:math-escape-preservation'
                        sh 'npm run test'
                        sh 'npm run build'
                        sh 'npm run build:e2e'
                        sh '''#!/usr/bin/env bash
set -euo pipefail
test "$(npx --no-install playwright --version)" = "Version 1.62.1"
test -d "$PLAYWRIGHT_BROWSERS_PATH"
'''

                        def groups = [
                            [name: 'Pilot core and orchestration', output: 'test-results/pilot-core', specs: [
                                'tests/wave1/e2e/foundation.spec.ts',
                                'tests/wave1/e2e/cloudflareFoundation.spec.ts',
                                'tests/wave2/e2e/pilotEntry.spec.ts',
                                'tests/wave3/e2e/pilotAssessment.spec.ts',
                                'tests/wave4/e2e/pilotLearning.spec.ts',
                                'tests/wave5/e2e/pilotJourney.spec.ts'
                            ]],
                            [name: 'Pilot no-games boundary', output: 'test-results/pilot-no-games', specs: [
                                'tests/wave6/e2e/noGames.spec.ts'
                            ]],
                            [name: 'Approved Pilot accessibility', output: 'test-results/pilot-a11y', specs: [
                                'tests/wave2/e2e/mobileLayout.spec.ts',
                                'tests/wave7/e2e/qualification.spec.ts'
                            ]]
                        ]
                        def groupResults = []
                        groups.each { group ->
                            def command = "npm run test:e2e:run -- --forbid-only --output=${group.output} ${group.specs.join(' ')}"
                            def exitCode = sh(returnStatus: true, script: command)
                            def result = exitCode == 0 ? 'SUCCESS' : 'FAILURE'
                            groupResults << "${group.name}: ${result}"
                            echo "${group.name}: ${result}"
                        }
                        env.JENKINS_SECONDARY_PLAYWRIGHT_RESULTS = groupResults.join('; ')
                        if (groupResults.any { !it.endsWith('SUCCESS') }) {
                            error('One or more required Playwright groups failed.')
                        }
                        env.JENKINS_SECONDARY_CI_RESULT = 'SUCCESS'
                    } catch (err) {
                        env.JENKINS_SECONDARY_CI_RESULT = currentBuild.currentResult == 'ABORTED' ? 'CANCELED' : 'FAILURE'
                        currentBuild.result = env.JENKINS_SECONDARY_CI_RESULT == 'CANCELED' ? 'ABORTED' : 'FAILURE'
                        echo 'Secondary Node 24 CI or Playwright verification failed; see stage output for the failing command.'
                        throw err
                    } finally {
                        deleteDir()
                    }
                }
            }
        }

        stage('Read-only production smoke') {
            when {
                expression { return smokeUrl }
            }
            agent {
                label 'setness-node24-ephemeral'
            }
            steps {
                script {
                    deleteDir()
                    try {
                        checkout scm
                        def checkedOutSha = sh(returnStdout: true, script: 'git rev-parse HEAD').trim().toLowerCase()
                        if (!(checkedOutSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/) ||
                            (env.CHANGE_ID && !secondaryCheckoutMatchesPrRevision(
                                checkedOutSha,
                                sh(returnStdout: true, script: 'git rev-list --parents -n 1 HEAD').trim(),
                                env.JENKINS_SECONDARY_PR_HEAD_SHA,
                                env.JENKINS_SECONDARY_PR_BASE_SHA
                            ))) {
                            error('Smoke checkout is neither the verified PR head nor its merge with the verified base.')
                        }
                        if (env.JENKINS_SECONDARY_CHECKED_OUT_SHA &&
                            env.JENKINS_SECONDARY_CHECKED_OUT_SHA != checkedOutSha) {
                            error('Smoke and CI checkouts did not resolve to the same revision.')
                        }
                        env.JENKINS_SECONDARY_CHECKED_OUT_SHA = checkedOutSha
                        def smokeExit = withEnv(["SMOKE_BASE_URL=${smokeUrl}"]) {
                            sh(returnStatus: true, script: 'node scripts/prod-smoke.mjs')
                        }
                        env.JENKINS_SECONDARY_SMOKE_RESULT = smokeExit == 0 ? 'SUCCESS' : 'FAILURE'
                        env.JENKINS_SECONDARY_SMOKE_DETAIL = smokeExit == 0
                            ? 'Read-only production smoke passed against the owner-configured endpoint.'
                            : 'Read-only production smoke failed; no deployment was attempted.'
                        echo env.JENKINS_SECONDARY_SMOKE_DETAIL
                    } catch (err) {
                        env.JENKINS_SECONDARY_SMOKE_RESULT = currentBuild.currentResult == 'ABORTED' ? 'CANCELED' : 'FAILURE'
                        env.JENKINS_SECONDARY_SMOKE_DETAIL = 'Read-only production smoke did not complete; no deployment was attempted.'
                        echo env.JENKINS_SECONDARY_SMOKE_DETAIL
                    } finally {
                        deleteDir()
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                def branchName = env.BRANCH_NAME ?: ''
                def changeId = env.CHANGE_ID?.trim()
                def isPullRequest = changeId != null || branchName.matches('PR-[0-9]+')
                def isMainBranch = branchName == 'main'
                if (isPullRequest || isMainBranch) {
                    def sha = isPullRequest
                        ? (env.JENKINS_SECONDARY_PR_HEAD_SHA ?: '')
                        : (env.JENKINS_SECONDARY_CHECKED_OUT_SHA ?: '')
                    if (!(sha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
                        currentBuild.result = 'FAILURE'
                        echo 'Could not verify the commit SHA; GitHub checks were not published against an unverified revision.'
                    } else {
                        def detailsUrl = secondaryCheckDetailsUrl(targetOwner, targetRepository, changeId, sha)
                        def authorization = env.JENKINS_SECONDARY_AUTHORIZATION ?: 'DENIED'
                        def ciResult = env.JENKINS_SECONDARY_CI_RESULT ?: 'NOT_RUN'
                        def smokeResult = env.JENKINS_SECONDARY_SMOKE_RESULT ?: 'NOT_RUN'
                        if (smokeResult == 'NOT_RUN' && currentBuild.currentResult == 'ABORTED') {
                            smokeResult = 'CANCELED'
                        }
                        def finalCiResult = isPullRequest && authorization != 'AUTHORIZED' ? 'FAILURE' :
                            (currentBuild.currentResult == 'ABORTED' || ciResult == 'CANCELED' ? 'CANCELED' :
                                ciResult == 'SUCCESS' ? 'SUCCESS' : 'FAILURE')
                        def smokeConclusion = secondarySmokeConclusion(smokeResult)
                        def smokeSummary = env.JENKINS_SECONDARY_SMOKE_DETAIL ?: 'No smoke result was recorded; inspect Jenkins before relying on it.'
                        if (smokeResult == 'NOT_RUN' && smokeUrl) {
                            smokeSummary = 'Not run: an earlier required verification stage prevented smoke from starting; no live request was made.'
                        } else if (smokeResult == 'CANCELED') {
                            smokeSummary = 'Canceled: the smoke stage did not complete; no passing result is claimed.'
                        }
                        if (isPullRequest && authorization != 'AUTHORIZED') {
                            smokeSummary = 'Not run: this PR was blocked before checkout or repository commands.'
                            smokeConclusion = 'NEUTRAL'
                        }
                        try {
                            publishChecks(
                                name: smokeCheckName,
                                title: "Production Smoke: ${smokeResult}",
                                summary: smokeSummary,
                                text: "Commit SHA: ${sha}\nAuthorization: ${authorization}\nSmoke outcome: ${smokeResult}\n${smokeSummary}",
                                detailsURL: detailsUrl,
                                status: 'COMPLETED',
                                conclusion: smokeConclusion
                            )
                        } catch (smokePublicationError) {
                            echo 'Could not publish the separate production-smoke result.'
                        }

                        if (isPullRequest || isMainBranch) {
                            def gateSummary = isPullRequest && authorization != 'AUTHORIZED'
                                ? 'Failed closed: owner-only policy rejected the PR before checkout.'
                                : "Node 24 verification ${finalCiResult.toLowerCase()}; Playwright groups: ${env.JENKINS_SECONDARY_PLAYWRIGHT_RESULTS ?: 'not completed'}; production smoke is reported separately."
                            def commitDescription = isPullRequest ? "pull request #${changeId}" : 'main branch push'
                            def revisionLine = isPullRequest
                                ? "Verified PR head SHA: ${sha}\nVerified PR base SHA: ${env.JENKINS_SECONDARY_PR_BASE_SHA}\nTested checkout SHA: ${env.JENKINS_SECONDARY_CHECKED_OUT_SHA ?: 'not completed'}"
                                : "Verified main commit SHA: ${sha}"
                            def gateText = """Commit type: ${commitDescription}
${revisionLine}
Authorization: ${authorization}
Node 24 CI: ${finalCiResult}
Playwright groups: ${env.JENKINS_SECONDARY_PLAYWRIGHT_RESULTS ?: 'not completed'}
Production smoke: ${smokeResult} (separate, non-required result)
No target Jenkinsfile was loaded; build workspace was deleted after each agent use.
"""
                            try {
                                publishChecks(
                                    name: primaryCheckName,
                                    title: "Required CI check: ${finalCiResult}",
                                    summary: gateSummary,
                                    text: gateText,
                                    detailsURL: detailsUrl,
                                    status: 'COMPLETED',
                                    conclusion: finalCiResult
                                )
                            } catch (gatePublicationError) {
                                currentBuild.result = 'FAILURE'
                                echo 'Could not publish the required CI result; the missing check remains fail-closed.'
                            }
                        }
                    }
                }
            }
        }
    }
}
