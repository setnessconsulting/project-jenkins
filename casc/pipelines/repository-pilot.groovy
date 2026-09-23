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

def candidatePathRules = /* JENKINS_PILOT_CANDIDATE_PATH_RULES */

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
                    assert candidateCheckConclusion('RELEVANT', 'NOT_RUN') == 'NEUTRAL'
                    assert candidateCheckConclusion('NOT_APPLICABLE', 'NOT_RUN') == 'NEUTRAL'
                    assert shouldFailGateClosed('UNCLASSIFIED', 'NOT_RUN', 'SUCCESS')
                    assert shouldFailGateClosed('RELEVANT', 'NOT_RUN', 'SUCCESS')
                    assert shouldFailGateClosed('RELEVANT', 'FAILURE', 'SUCCESS')
                    assert !shouldFailGateClosed('RELEVANT', 'NOT_RUN', 'FAILURE')
                    assert !shouldFailGateClosed('RELEVANT', 'SUCCESS', 'SUCCESS')
                    assert !shouldFailGateClosed('NOT_APPLICABLE', 'NOT_RUN', 'SUCCESS')

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
                            env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT = 'FAILURE'
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
                        def candidateState = env.JENKINS_CLOUDFLARE_CANDIDATE ?: 'UNCLASSIFIED'
                        def candidateApplicable = candidateState == 'RELEVANT'
                        def candidateRunResult = env.JENKINS_CLOUDFLARE_CANDIDATE_RESULT ?: 'NOT_RUN'
                        def result = candidateCheckConclusion(candidateState, candidateRunResult)
                        if (shouldFailGateClosed(candidateState, candidateRunResult, currentBuild.currentResult)) {
                            currentBuild.result = 'FAILURE'
                        }
                        def summary = candidateState == 'UNCLASSIFIED'
                            ? 'Unable to classify this pull request for Cloudflare Candidate checks; jenkins-pr-gate must fail closed.'
                            : (candidateApplicable
                                ? (candidateRunResult != 'SUCCESS' && candidateRunResult != 'FAILURE'
                                    ? 'Cloudflare Candidate checks were not run because an earlier stage did not complete or the build was cancelled; see jenkins-pr-gate.'
                                    : "Cloudflare Candidate ${candidateRunResult.toLowerCase()} for ${env.JENKINS_CLOUDFLARE_CHANGED_PATH_COUNT} relevant changed path(s).")
                                : 'Not applicable: no configured Cloudflare Candidate path changed.')

                        publishChecks(
                            name: 'cloudflare-candidate',
                            title: candidateApplicable ? 'Cloudflare Candidate' : 'Cloudflare Candidate (not applicable)',
                            summary: summary,
                            status: 'COMPLETED',
                            conclusion: result
                        )
                    }
                }
                finally {
                    deleteDir()
                }
            }
        }
    }
}
