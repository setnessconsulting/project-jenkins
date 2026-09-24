String classifyCandidateChanges(List<String> changedPaths, List<String> pathRules) {
    for (String path : changedPaths) {
        if (path.toLowerCase().endsWith('.md')) {
            continue
        }
        for (String rule : pathRules) {
            if (rule.endsWith('/') ? path.startsWith(rule) : path == rule) {
                return 'RELEVANT'
            }
        }
    }
    return 'NOT_APPLICABLE'
}

String candidateCheckConclusion(String candidateState, String candidateResult) {
    if (candidateState == 'UNCLASSIFIED') {
        return 'FAILURE'
    }
    if (candidateState in ['NOT_APPLICABLE', 'BLOCKED']) {
        return 'NEUTRAL'
    }
    if (candidateState != 'RELEVANT') {
        return 'FAILURE'
    }
    if (candidateResult == 'SUCCESS' || candidateResult == 'FAILURE') {
        return candidateResult
    }
    if (candidateResult == 'CANCELED') {
        return 'CANCELED'
    }
    return 'NEUTRAL'
}

boolean shouldFailGateClosed(String candidateState, String candidateResult, String primaryResult) {
    if (!(candidateState in ['RELEVANT', 'NOT_APPLICABLE'])) {
        return true
    }
    return candidateState == 'RELEVANT' &&
        primaryResult == 'SUCCESS' &&
        candidateResult != 'SUCCESS'
}

boolean isAuthorizedPullRequestAuthor(String author, List<String> trustedAuthors) {
    def normalizedAuthor = author?.trim()
    return normalizedAuthor != null && !normalizedAuthor.isEmpty() &&
        trustedAuthors.any { trusted -> trusted.equalsIgnoreCase(normalizedAuthor) }
}

String verifiedPullRequestHeadSha(def run, String expectedChangeId) {
    if (expectedChangeId == null || !(expectedChangeId ==~ /[0-9]+/)) {
        return null
    }
    def revisionAction = run.getAction(jenkins.scm.api.SCMRevisionAction.class)
    def revision = revisionAction?.getRevision()
    if (!(revision instanceof org.jenkinsci.plugins.github_branch_source.PullRequestSCMRevision)) {
        return null
    }
    def pullRequestHead = revision.getHead()
    if (!(pullRequestHead instanceof org.jenkinsci.plugins.github_branch_source.PullRequestSCMHead) ||
        pullRequestHead.getId() != expectedChangeId) {
        return null
    }
    def targetOwner = System.getenv('JENKINS_TARGET_REPO_OWNER')?.trim()
    def targetRepository = System.getenv('JENKINS_TARGET_REPO_NAME')?.trim()
    if (!targetOwner || !targetRepository ||
        !targetOwner.equalsIgnoreCase(pullRequestHead.getSourceOwner() ?: '') ||
        !targetRepository.equalsIgnoreCase(pullRequestHead.getSourceRepo() ?: '')) {
        return null
    }
    def headSha = revision.getPullHash()
    if (headSha == null || !(headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
        return null
    }
    return headSha.toLowerCase()
}

String gateCheckConclusion(String buildResult) {
    switch (buildResult) {
        case 'SUCCESS': return 'SUCCESS'
        case 'ABORTED': return 'CANCELED'
        default: return 'FAILURE'
    }
}

String candidateCheckSummary(String authorization, String candidateState, String candidateResult, String changedPathCount) {
    if (authorization != 'AUTHORIZED') {
        return 'Not run: owner-only policy rejected this PR before checkout or repository commands.'
    }
    if (candidateState == 'UNCLASSIFIED') {
        return 'Unable to classify this pull request for candidate checks; the required CI result must fail closed.'
    }
    if (candidateState == 'BLOCKED') {
        return 'Not run: owner-only policy blocked this PR before checkout or repository commands.'
    }
    if (candidateState == 'NOT_APPLICABLE') {
        return 'Not applicable: no configured Cloudflare Candidate path changed.'
    }
    if (candidateResult == 'SUCCESS' || candidateResult == 'FAILURE') {
        return "Cloudflare Candidate ${candidateResult.toLowerCase()} for ${changedPathCount} relevant changed path(s)."
    }
    if (candidateResult == 'CANCELED') {
        return 'Cancelled: candidate checks stopped before completion; see the required CI result.'
    }
    if (candidateResult == 'NOT_RUN') {
        return 'Not run: standard CI did not complete before candidate checks could run; see the required CI result.'
    }
    return 'Cloudflare Candidate result is unknown; failing closed.'
}

def candidatePathRules = /* JENKINS_PILOT_CANDIDATE_PATH_RULES */
def trustedPullRequestAuthors = /* JENKINS_PILOT_TRUSTED_PR_AUTHORS */
def primaryCheckName = /* JENKINS_PILOT_PRIMARY_CHECK_NAME */
def candidateCheckName = /* JENKINS_PILOT_CANDIDATE_CHECK_NAME */
def appDirectory = /* JENKINS_PILOT_APP_DIRECTORY */

pipeline {
    agent none

    options {
        timeout(time: 90, unit: 'MINUTES')
        disableConcurrentBuilds(abortPrevious: true)
        skipDefaultCheckout(true)
    }

    environment {
        NEXT_PUBLIC_SITE_URL = /* JENKINS_PILOT_SITE_URL */
    }

    stages {
        stage('Authorize pull request') {
            steps {
                script {
                    def branchName = env.BRANCH_NAME ?: ''
                    def changeId = env.CHANGE_ID?.trim()
                    def isPullRequest = changeId != null || branchName.matches('PR-[0-9]+')
                    env.JENKINS_PILOT_AUTHORIZATION = isPullRequest ? 'DENIED' : 'NOT_A_PR'

                    def verifiedHeadSha = isPullRequest
                        ? verifiedPullRequestHeadSha(currentBuild.rawBuild, changeId)
                        : null
                    if (isPullRequest && verifiedHeadSha == null) {
                        error('Could not verify the GitHub Branch Source PR head SHA; no checkout or repository command was run, and no check will be published against an unverified revision.')
                    }
                    if (isPullRequest) {
                        env.JENKINS_PILOT_PR_HEAD_SHA = verifiedHeadSha
                    }

                    if (isPullRequest && !isAuthorizedPullRequestAuthor(env.CHANGE_AUTHOR, trustedPullRequestAuthors)) {
                        env.JENKINS_CLOUDFLARE_CANDIDATE = 'BLOCKED'
                        env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT = 'NOT_RUN'
                        env.JENKINS_PILOT_STANDARD_RESULT = 'NOT_RUN'

                        // This stage has no agent/workspace. The controller verified the
                        // Branch Source PullRequestSCMRevision head SHA above before publishing.
                        // The Checks plugin resolves that same build revision; a publish error
                        // leaves the result missing/pending and therefore fails closed.
                        try {
                            publishChecks(
                                name: primaryCheckName,
                                title: 'Required CI check: BLOCKED',
                                summary: 'Failed closed: owner-only shadow policy rejected this PR before checkout.',
                                text: "PR #${changeId}\nVerified PR head SHA: ${verifiedHeadSha}\nAuthor: ${env.CHANGE_AUTHOR ?: 'unknown'}\nNo checkout or repository command was run.",
                                status: 'COMPLETED',
                                conclusion: 'FAILURE'
                            )
                            publishChecks(
                                name: candidateCheckName,
                                title: 'Cloudflare Candidate (blocked)',
                                summary: 'Not run: owner-only policy blocked this PR before checkout or repository commands.',
                                text: "PR #${changeId}\nVerified PR head SHA: ${verifiedHeadSha}\nCandidate applicability was not evaluated because this PR was denied.",
                                status: 'COMPLETED',
                                conclusion: 'NEUTRAL'
                            )
                        } catch (publicationError) {
                            currentBuild.result = 'FAILURE'
                            echo 'Controller could not publish the pre-checkout policy result; no target code will run and a missing required check remains fail-closed.'
                        }
                        error('Owner-only Jenkins shadow: PR author is not allowlisted; no target checkout or repository command was run.')
                    }

                    if (isPullRequest) {
                        env.JENKINS_PILOT_AUTHORIZATION = 'AUTHORIZED'
                        try {
                            publishChecks(
                                name: candidateCheckName,
                                title: 'Cloudflare Candidate (classification pending)',
                                summary: 'Checking Candidate applicability; no Candidate commands have run yet.',
                                text: "PR #${changeId}; verified head ${verifiedHeadSha}: awaiting trusted changed-path classification.",
                                status: 'IN_PROGRESS'
                            )
                        } catch (publicationError) {
                            error('Could not publish the controller-side Candidate status; failing closed before checkout.')
                        }
                    }
                }
            }
        }

        stage('Pipeline policy self-test') {
            steps {
                script {
                    assert classifyCandidateChanges([], candidatePathRules) == 'NOT_APPLICABLE'

                    def relevantFixtures = candidatePathRules.collect { rule ->
                        rule.endsWith('/') ? "${rule}jenkins-policy-fixture.txt" : rule
                    }
                    relevantFixtures.each { fixture ->
                        assert classifyCandidateChanges([fixture], candidatePathRules) == 'RELEVANT'
                    }

                    def directoryRules = candidatePathRules.findAll { rule -> rule.endsWith('/') }
                    directoryRules.each { rule ->
                        assert classifyCandidateChanges(["${rule}README.md"], candidatePathRules) == 'NOT_APPLICABLE'
                        assert classifyCandidateChanges(["${rule}pilot-example.mdx"], candidatePathRules) == 'RELEVANT'
                    }

                    def irrelevantFixture = '__jenkins-policy-self-test__/unmatched.txt'
                    while (classifyCandidateChanges([irrelevantFixture], candidatePathRules) != 'NOT_APPLICABLE') {
                        irrelevantFixture = "_${irrelevantFixture}"
                    }

                    assert candidateCheckConclusion('UNCLASSIFIED', 'NOT_RUN') == 'FAILURE'
                    assert candidateCheckConclusion('RELEVANT', 'SUCCESS') == 'SUCCESS'
                    assert candidateCheckConclusion('RELEVANT', 'FAILURE') == 'FAILURE'
                    assert candidateCheckConclusion('RELEVANT', 'CANCELED') == 'CANCELED'
                    assert candidateCheckConclusion('RELEVANT', 'NOT_RUN') == 'NEUTRAL'
                    assert candidateCheckConclusion('NOT_APPLICABLE', 'NOT_RUN') == 'NEUTRAL'
                    assert candidateCheckConclusion('BLOCKED', 'NOT_RUN') == 'NEUTRAL'
                    assert shouldFailGateClosed('UNCLASSIFIED', 'NOT_RUN', 'SUCCESS')
                    assert shouldFailGateClosed('RELEVANT', 'NOT_RUN', 'SUCCESS')
                    assert shouldFailGateClosed('RELEVANT', 'FAILURE', 'SUCCESS')
                    assert !shouldFailGateClosed('RELEVANT', 'NOT_RUN', 'FAILURE')
                    assert !shouldFailGateClosed('RELEVANT', 'SUCCESS', 'SUCCESS')
                    assert !shouldFailGateClosed('NOT_APPLICABLE', 'NOT_RUN', 'SUCCESS')
                    assert isAuthorizedPullRequestAuthor(trustedPullRequestAuthors[0], trustedPullRequestAuthors)
                    assert !isAuthorizedPullRequestAuthor('untrusted-contributor', trustedPullRequestAuthors)
                    assert !isAuthorizedPullRequestAuthor(null, trustedPullRequestAuthors)
                    assert gateCheckConclusion('SUCCESS') == 'SUCCESS'
                    assert gateCheckConclusion('FAILURE') == 'FAILURE'
                    assert gateCheckConclusion('ABORTED') == 'CANCELED'
                    assert candidateCheckSummary('AUTHORIZED', 'NOT_APPLICABLE', 'NOT_RUN', '0') ==
                        'Not applicable: no configured Cloudflare Candidate path changed.'
                    assert candidateCheckSummary('DENIED', 'BLOCKED', 'NOT_RUN', '0').startsWith('Not run: owner-only policy')
                    assert candidateCheckSummary('AUTHORIZED', 'RELEVANT', 'CANCELED', '2').startsWith('Cancelled:')
                    assert candidateCheckSummary('AUTHORIZED', 'RELEVANT', 'NOT_RUN', '2').startsWith('Not run: Standard CI')
                    assert candidateCheckSummary('AUTHORIZED', 'RELEVANT', 'FAILURE', '2').contains('failure for 2 relevant changed path(s)')

                    echo 'Jenkins gate policy self-test passed.'
                }
            }
        }

        stage('Execute trusted checks') {
            agent {
                label 'setness-ephemeral'
            }

            steps {
                script {
                    env.JENKINS_CLOUDFLARE_CANDIDATE = 'UNCLASSIFIED'
                    env.JENKINS_CLOUDFLARE_CHANGED_PATH_COUNT = '0'
                    env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT = 'NOT_RUN'
                    env.JENKINS_PILOT_STANDARD_RESULT = 'NOT_RUN'

                    try {
                        stage('Checkout and classify') {
                            deleteDir()
                            checkout scm

                            def branchName = env.BRANCH_NAME ?: ''
                            def changeId = env.CHANGE_ID?.trim()
                            def isPullRequest = changeId != null || branchName.matches('PR-[0-9]+')
                            env.JENKINS_CLOUDFLARE_CANDIDATE = isPullRequest
                                ? 'UNCLASSIFIED'
                                : 'NOT_APPLICABLE'

                            if (isPullRequest) {
                                // Origin PR discovery builds a synthetic merge. Compare its
                                // target/base first parent with the merge result so Candidate
                                // paths describe the changes being proposed by this PR.
                                def diff = sh(
                                    returnStdout: true,
                                    script: 'git diff --name-only HEAD^1 HEAD'
                                ).trim()
                                def changedPaths = diff ? diff.readLines() : []
                                def candidatePaths = changedPaths.findAll { path ->
                                    classifyCandidateChanges([path], candidatePathRules) == 'RELEVANT'
                                }
                                env.JENKINS_CLOUDFLARE_CHANGED_PATH_COUNT = candidatePaths.size().toString()
                                env.JENKINS_CLOUDFLARE_CANDIDATE = candidatePaths.isEmpty()
                                    ? 'NOT_APPLICABLE'
                                    : 'RELEVANT'

                                if (env.JENKINS_CLOUDFLARE_CANDIDATE == 'NOT_APPLICABLE') {
                                    publishChecks(
                                        name: candidateCheckName,
                                        title: 'Cloudflare Candidate (not applicable)',
                                        summary: 'Not applicable: no configured Cloudflare Candidate path changed.',
                                        text: "PR #${changeId}: Candidate path classification completed before standard CI.",
                                        status: 'COMPLETED',
                                        conclusion: 'NEUTRAL'
                                    )
                                }
                            }
                        }

                        stage('Standard CI') {
                            dir(appDirectory) {
                                try {
                                    stage('Node 22 runtime') {
                                        sh '''#!/usr/bin/env bash
set -euo pipefail

test "$(node --version)" = "v22.23.2"
node --version
npm --version
'''
                                    }
                                    stage('Install dependencies (npm ci)') {
                                        sh 'npm ci'
                                    }
                                    stage('Typecheck') {
                                        sh 'npm run typecheck'
                                    }
                                    stage('Lint') {
                                        sh 'npm run lint'
                                    }
                                    stage('Build') {
                                        sh 'npm run build'
                                    }
                                    stage('Blog validation') {
                                        sh 'npm run blog:validate'
                                    }
                                    stage('SEO baseline') {
                                        sh 'npm run seo:baseline'
                                    }
                                    stage('Tests') {
                                        sh 'npm run test'
                                    }
                                    env.JENKINS_PILOT_STANDARD_RESULT = 'SUCCESS'
                                } catch (err) {
                                    env.JENKINS_PILOT_STANDARD_RESULT = currentBuild.currentResult == 'ABORTED'
                                        ? 'CANCELED'
                                        : 'FAILURE'
                                    throw err
                                }
                            }
                        }

                        def branchName = env.BRANCH_NAME ?: ''
                        def changeId = env.CHANGE_ID?.trim()
                        def isPullRequest = changeId || branchName.matches('PR-[0-9]+')
                        if (isPullRequest && env.JENKINS_CLOUDFLARE_CANDIDATE == 'RELEVANT') {
                            stage('Cloudflare Candidate') {
                                dir(appDirectory) {
                                    withEnv(['CLOUDFLARE_ENV=staging']) {
                                        try {
                                            stage('MDX validation') {
                                                sh 'npm run mdx:check'
                                            }
                                            stage('Vinext check') {
                                                sh 'npx vinext check'
                                            }
                                            stage('Vinext staging build') {
                                                sh 'npm run build:vinext:staging'
                                            }
                                            stage('Cloudflare configuration validation') {
                                                sh 'npm run cloudflare:validate'
                                            }
                                            stage('Wrangler validation') {
                                                sh 'npm run wrangler:check'
                                            }
                                            stage('Wrangler dry-run deploy') {
                                                sh 'npx wrangler deploy --dry-run --config dist/server/wrangler.json'
                                            }
                                            env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT = 'SUCCESS'
                                        } catch (err) {
                                            env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT = currentBuild.currentResult == 'ABORTED'
                                                ? 'CANCELED'
                                                : 'FAILURE'
                                            throw err
                                        }
                                    }
                                }
                            }
                        }

                        stage('Reviewer result summary') {
                            def standardResult = env.JENKINS_PILOT_STANDARD_RESULT ?: 'NOT_RUN'
                            def candidateState = env.JENKINS_CLOUDFLARE_CANDIDATE ?: 'UNCLASSIFIED'
                            def candidateResult = env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT ?: 'NOT_RUN'
                            def candidateSummary = candidateState == 'NOT_APPLICABLE'
                                ? 'not applicable'
                                : "${candidateState.toLowerCase()} / ${candidateResult.toLowerCase()}"
                            echo "Standard CI: ${standardResult}; Cloudflare Candidate: ${candidateState} (${candidateResult})."
                            echo "Reviewer result: Standard CI ${standardResult.toLowerCase()}; Cloudflare Candidate ${candidateSummary}."
                        }
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
                def isPullRequest = changeId || branchName.matches('PR-[0-9]+')
                if (isPullRequest) {
                    def verifiedHeadSha = env.JENKINS_PILOT_PR_HEAD_SHA ?: ''
                    if (!(verifiedHeadSha ==~ /(?i)[0-9a-f]{40}|[0-9a-f]{64}/)) {
                        currentBuild.result = 'FAILURE'
                        echo 'Could not verify the PR head SHA; no GitHub checks were published and no repository code was run.'
                    } else {
                        def authorization = env.JENKINS_PILOT_AUTHORIZATION ?: 'DENIED'
                        def candidateState = env.JENKINS_CLOUDFLARE_CANDIDATE ?:
                            (authorization == 'AUTHORIZED' ? 'UNCLASSIFIED' : 'BLOCKED')
                        def candidateApplicable = candidateState == 'RELEVANT'
                        def candidateRunResult = env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT ?: 'NOT_RUN'
                        def candidateConclusion = candidateCheckConclusion(candidateState, candidateRunResult)
                        if (shouldFailGateClosed(candidateState, candidateRunResult, currentBuild.currentResult)) {
                            currentBuild.result = 'FAILURE'
                        }

                        def candidateSummary = candidateCheckSummary(
                            authorization,
                            candidateState,
                            candidateRunResult,
                            env.JENKINS_CLOUDFLARE_CHANGED_PATH_COUNT ?: '0'
                        )
                        try {
                            publishChecks(
                                name: candidateCheckName,
                                title: candidateApplicable ? 'Cloudflare Candidate' : 'Cloudflare Candidate (not applicable/blocked)',
                                summary: candidateSummary,
                                text: "PR #${changeId ?: 'unknown'}\nVerified PR head SHA: ${verifiedHeadSha}\nAuthorization: ${authorization}\nCandidate status: ${candidateState}\nCandidate suite result: ${candidateRunResult}",
                                status: 'COMPLETED',
                                conclusion: candidateConclusion
                            )
                        } catch (publicationError) {
                            currentBuild.result = 'FAILURE'
                            echo 'Could not publish the candidate check; failing closed.'
                        }

                        def standardResult = env.JENKINS_PILOT_STANDARD_RESULT ?: 'NOT_RUN'
                        def finalResult = currentBuild.currentResult ?: 'FAILURE'
                        def gateCandidateSummary = candidateApplicable
                            ? candidateRunResult.toLowerCase()
                            : candidateState == 'BLOCKED' ? 'blocked before checkout' : 'not applicable'
                        def gateSummary = authorization != 'AUTHORIZED'
                            ? 'Failed closed: this owner-only shadow rejected the PR before checkout or repository commands.'
                            : "Standard CI ${standardResult.toLowerCase()}; Cloudflare Candidate ${gateCandidateSummary}."
                        def gateText = """Pull request: #${changeId ?: 'unknown'}
Verified PR head SHA: ${env.JENKINS_PILOT_PR_HEAD_SHA ?: 'unverified'}
Authorization: ${authorization}
Standard CI: ${standardResult}
Cloudflare Candidate: ${candidateState} (${candidateRunResult})
Final Jenkins result: ${finalResult}

Standard suite: Node 22, npm ci, typecheck, lint, build, blog validation, SEO baseline, tests.
Candidate suite (when applicable): MDX, Vinext check and staging build, Cloudflare config, Wrangler validation, dry-run deploy.
"""

                        try {
                            publishChecks(
                                name: primaryCheckName,
                                title: "Required CI check: ${finalResult}",
                                summary: gateSummary,
                                text: gateText,
                                status: 'COMPLETED',
                                conclusion: gateCheckConclusion(finalResult)
                            )
                        } catch (publicationError) {
                            currentBuild.result = 'FAILURE'
                            echo 'Could not publish the required CI check; the missing result remains fail-closed.'
                        }
                    }
                }
            }
        }
    }
}
