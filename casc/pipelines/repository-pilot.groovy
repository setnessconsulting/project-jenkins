String classifyCandidateChanges(List<String> changedPaths, List<String> pathRules) {
    for (String path : changedPaths) {
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
    if (candidateState == 'NOT_APPLICABLE') {
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
        return 'Unable to classify this pull request for Cloudflare Candidate checks; jenkins-pr-gate must fail closed.'
    }
    if (candidateState == 'NOT_APPLICABLE') {
        return 'Not applicable: no configured Cloudflare Candidate path changed.'
    }
    if (candidateResult == 'SUCCESS' || candidateResult == 'FAILURE') {
        return "Cloudflare Candidate ${candidateResult.toLowerCase()} for ${changedPathCount} relevant changed path(s)."
    }
    return 'Cloudflare Candidate checks were not run because an earlier stage did not complete or the build was cancelled; see jenkins-pr-gate.'
}

def candidatePathRules = /* JENKINS_PILOT_CANDIDATE_PATH_RULES */
def trustedPullRequestAuthors = /* JENKINS_PILOT_TRUSTED_PR_AUTHORS */

pipeline {
    agent {
        label 'setness-linux'
    }

    options {
        timeout(time: 90, unit: 'MINUTES')
        disableConcurrentBuilds(abortPrevious: true)
        skipDefaultCheckout(true)
    }

    environment {
        NEXT_PUBLIC_SITE_URL = 'https://setnessconsulting.com'
        NPM_CONFIG_CACHE = "${env.WORKSPACE}/.npm-cache"
    }

    stages {
        stage('Authorize pull request') {
            steps {
                script {
                    def branchName = env.BRANCH_NAME ?: ''
                    def changeId = env.CHANGE_ID?.trim()
                    def isPullRequest = changeId || branchName.matches('PR-[0-9]+')
                    env.JENKINS_PILOT_AUTHORIZATION = isPullRequest ? 'DENIED' : 'NOT_A_PR'

                    if (isPullRequest) {
                        if (!isAuthorizedPullRequestAuthor(env.CHANGE_AUTHOR, trustedPullRequestAuthors)) {
                            error('Owner-only Jenkins shadow: PR author is not allowlisted; no target checkout or repository command was run.')
                        }
                        env.JENKINS_PILOT_AUTHORIZATION = 'AUTHORIZED'
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
                    assert candidateCheckSummary('DENIED', 'UNCLASSIFIED', 'NOT_RUN', '0').startsWith('Not run: owner-only policy')
                    assert candidateCheckSummary('AUTHORIZED', 'RELEVANT', 'FAILURE', '2').contains('failure for 2 relevant changed path(s)')

                    echo 'Jenkins gate policy self-test passed.'
                }
            }
        }

        stage('Checkout and classify') {
            steps {
                deleteDir()
                checkout scm
                script {
                    def branchName = env.BRANCH_NAME ?: ''
                    def changeId = env.CHANGE_ID?.trim()
                    def isPullRequest = changeId || branchName.matches('PR-[0-9]+')

                    // Keep these mutable run values out of Declarative's
                    // environment block; its values can shadow env assignments.
                    env.JENKINS_CLOUDFLARE_CANDIDATE = isPullRequest
                        ? 'UNCLASSIFIED'
                        : 'NOT_APPLICABLE'
                    env.JENKINS_CLOUDFLARE_CHANGED_PATH_COUNT = '0'
                    env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT = 'NOT_RUN'
                    env.JENKINS_PILOT_STANDARD_RESULT = 'NOT_RUN'

                    if (isPullRequest) {
                        // GitHub Branch Source is configured to build the PR
                        // merge revision. Compare it with the first parent
                        // (target branch) so first-build changelog gaps cannot
                        // silently classify a relevant PR as not applicable.
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

                        if (env.JENKINS_CLOUDFLARE_CANDIDATE == 'UNCLASSIFIED') {
                            error('Unable to classify this pull request for Cloudflare Candidate checks; failing closed.')
                        }
                    }

                    echo "Cloudflare Candidate classification: ${env.JENKINS_CLOUDFLARE_CANDIDATE}"
                }
            }
        }

        stage('Standard CI') {
            steps {
                dir('web') {
                    script {
                        try {
                            sh '''#!/usr/bin/env bash
set -euo pipefail

test "$(node --version)" = "v22.23.2"
node --version
npm --version
npm ci
npm run typecheck
npm run lint
npm run build
npm run blog:validate
npm run seo:baseline
npm run test
'''
                            env.JENKINS_PILOT_STANDARD_RESULT = 'SUCCESS'
                        } catch (err) {
                            env.JENKINS_PILOT_STANDARD_RESULT = currentBuild.currentResult == 'ABORTED'
                                ? 'CANCELED'
                                : 'FAILURE'
                            throw err
                        }
                    }
                }
            }
        }

        stage('Cloudflare Candidate') {
            when {
                expression {
                    def branchName = env.BRANCH_NAME ?: ''
                    def changeId = env.CHANGE_ID?.trim()
                    def isPullRequest = changeId || branchName.matches('PR-[0-9]+')
                    return isPullRequest && env.JENKINS_CLOUDFLARE_CANDIDATE == 'RELEVANT'
                }
            }
            steps {
                dir('web') {
                    script {
                        try {
                            sh '''#!/usr/bin/env bash
set -euo pipefail

npm run mdx:check
npx vinext check
npm run build:vinext:staging
CLOUDFLARE_ENV=staging npm run cloudflare:validate
npm run wrangler:check
npx wrangler deploy --dry-run --config dist/server/wrangler.json
'''
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
    }

    post {
        always {
            script {
                try {
                    def branchName = env.BRANCH_NAME ?: ''
                    def changeId = env.CHANGE_ID?.trim()
                    def isPullRequest = changeId || branchName.matches('PR-[0-9]+')
                    if (isPullRequest) {
                        def authorization = env.JENKINS_PILOT_AUTHORIZATION ?: 'DENIED'
                        def candidateState = authorization == 'AUTHORIZED'
                            ? (env.JENKINS_CLOUDFLARE_CANDIDATE ?: 'UNCLASSIFIED')
                            : 'UNCLASSIFIED'
                        def candidateApplicable = candidateState == 'RELEVANT'
                        def candidateRunResult = env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT ?: 'NOT_RUN'
                        def candidateConclusion = authorization == 'AUTHORIZED'
                            ? candidateCheckConclusion(candidateState, candidateRunResult)
                            : 'FAILURE'
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
                                name: 'cloudflare-candidate',
                                title: candidateApplicable ? 'Cloudflare Candidate' : 'Cloudflare Candidate (not applicable)',
                                summary: candidateSummary,
                                text: "PR #${changeId ?: 'unknown'}\nAuthorization: ${authorization}\nCandidate status: ${candidateState}\nCandidate suite result: ${candidateRunResult}",
                                status: 'COMPLETED',
                                conclusion: candidateConclusion
                            )
                        } catch (err) {
                            currentBuild.result = 'FAILURE'
                            echo 'Could not publish cloudflare-candidate.'
                        }

                        def standardResult = env.JENKINS_PILOT_STANDARD_RESULT ?: 'NOT_RUN'
                        def finalResult = currentBuild.currentResult ?: 'FAILURE'
                        def gateCandidateSummary = candidateApplicable
                            ? candidateRunResult.toLowerCase()
                            : 'not applicable'
                        def gateSummary = authorization != 'AUTHORIZED'
                            ? 'Failed closed: this owner-only shadow rejected the PR before checkout or repository commands.'
                            : "Standard CI ${standardResult.toLowerCase()}; Cloudflare Candidate ${gateCandidateSummary}."
                        def gateText = """Pull request: #${changeId ?: 'unknown'}
Authorization: ${authorization}
Standard CI: ${standardResult}
Cloudflare Candidate: ${candidateState} (${candidateRunResult})
Final Jenkins result: ${finalResult}

Standard suite: Node 22, npm ci, typecheck, lint, build, blog validation, SEO baseline, tests.
Candidate suite (when applicable): MDX, Vinext check and staging build, Cloudflare config, Wrangler validation, dry-run deploy.
"""

                        try {
                            publishChecks(
                                name: 'jenkins-pr-gate',
                                title: "Jenkins PR gate: ${finalResult}",
                                summary: gateSummary,
                                text: gateText,
                                status: 'COMPLETED',
                                conclusion: gateCheckConclusion(finalResult)
                            )
                        } catch (err) {
                            currentBuild.result = 'FAILURE'
                            echo 'Could not publish jenkins-pr-gate.'
                        }
                    }
                }
                finally {
                    deleteDir()
                }
            }
        }
    }
}
