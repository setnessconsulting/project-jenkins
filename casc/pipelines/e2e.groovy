def repositoryUrl = /* JENKINS_PILOT_E2E_REPOSITORY */
def checkDetailsBase = /* JENKINS_PILOT_E2E_DETAILS_BASE */
def checkoutCredentialId = /* JENKINS_PILOT_E2E_CHECKOUT_CREDENTIAL_ID */
def appCredentialId = /* JENKINS_PILOT_E2E_APP_CREDENTIAL_ID */
def expectedAppId = /* JENKINS_PILOT_E2E_APP_ID */
def targetOwner = /* JENKINS_PILOT_E2E_REPOSITORY_OWNER */
def targetRepository = /* JENKINS_PILOT_E2E_REPOSITORY_NAME */
def appDirectory = /* JENKINS_PILOT_E2E_APP_DIRECTORY */

@com.cloudbees.groovy.cps.NonCPS
Map githubChecksRequest(
    String method,
    String endpoint,
    String token,
    Map payload,
    int expectedStatus
) {
    int responseStatus = -1
    try {
        def request = java.net.http.HttpRequest.newBuilder(java.net.URI.create(endpoint))
            .timeout(java.time.Duration.ofSeconds(20))
            .header('Accept', 'application/vnd.github+json')
            .header('Authorization', "Bearer ${token}")
            .header('X-GitHub-Api-Version', '2022-11-28')
            .header('Content-Type', 'application/json; charset=utf-8')
            .method(method, java.net.http.HttpRequest.BodyPublishers.ofString(
                groovy.json.JsonOutput.toJson(payload),
                java.nio.charset.StandardCharsets.UTF_8
            ))
            .build()
        def client = java.net.http.HttpClient.newBuilder()
            .connectTimeout(java.time.Duration.ofSeconds(10))
            .build()
        def response = client.send(request, java.net.http.HttpResponse.BodyHandlers.ofString(java.nio.charset.StandardCharsets.UTF_8))
        responseStatus = response.statusCode()
        if (responseStatus != expectedStatus) {
            throw new IllegalStateException("GitHub Checks API returned HTTP ${responseStatus}.")
        }
        return (Map) new groovy.json.JsonSlurperClassic().parseText(response.body())
    } catch (InterruptedException ignored) {
        Thread.currentThread().interrupt()
        throw new IllegalStateException('The explicit GitHub Checks API request was interrupted.')
    } catch (Exception ignored) {
        // Never include request headers, credential values, or raw API bodies in build logs.
        String statusHint = responseStatus >= 0 ? " (HTTP ${responseStatus})" : ''
        throw new IllegalStateException("The explicit GitHub Checks API request failed${statusHint}; verify controller networking and App credential configuration.")
    }
}

@com.cloudbees.groovy.cps.NonCPS
Map createE2eCheck(
    def run,
    String credentialId,
    String owner,
    String repository,
    String appId,
    String headSha,
    String detailsUrl,
    String startedAt
) {
    if (!(owner ==~ /[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/) ||
        !(repository ==~ /[A-Za-z0-9._-]{1,100}/) ||
        !(appId ==~ /[0-9]{1,20}/) ||
        !(headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/) ||
        !detailsUrl.startsWith("https://github.com/${owner}/${repository}/commit/${headSha}/checks")) {
        throw new IllegalArgumentException('The trusted E2E publisher received invalid repository, App, SHA, or details metadata.')
    }

    def credential = com.cloudbees.plugins.credentials.CredentialsProvider.findCredentialById(
        credentialId,
        org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials.class,
        run,
        java.util.Collections.emptyList()
    )
    if (credential == null) {
        throw new IllegalStateException('The controller could not resolve the configured GitHub App credential.')
    }
    String installationToken = credential.getPassword()?.getPlainText()
    if (!installationToken) {
        throw new IllegalStateException('The configured GitHub App credential did not provide an installation token.')
    }

    String endpoint = "https://api.github.com/repos/${owner}/${repository}/check-runs"
    Map response = githubChecksRequest('POST', endpoint, installationToken, [
        name: 'jenkins-e2e',
        head_sha: headSha.toLowerCase(),
        status: 'in_progress',
        started_at: startedAt,
        details_url: detailsUrl,
        external_id: "jenkins:${run.getExternalizableId()}",
        output: [
            title: 'Playwright E2E: RUNNING',
            summary: "Scheduled/manual Playwright verification started on exact commit ${headSha.toLowerCase()}.",
            text: 'Suites: standard Playwright E2E, finance fail-closed, and AI skills pack.'
        ]
    ], 201)

    if (!(response.id instanceof Number)) {
        throw new IllegalStateException('GitHub did not return a check-run identifier.')
    }
    return [
        id: response.id.toString(),
        name: response.name?.toString() ?: '',
        headSha: response.head_sha?.toString() ?: '',
        appId: response.app?.id?.toString() ?: ''
    ]
}

@com.cloudbees.groovy.cps.NonCPS
void completeE2eCheck(
    def run,
    String credentialId,
    String owner,
    String repository,
    String appId,
    String checkRunId,
    String headSha,
    String detailsUrl,
    String conclusion,
    String completedAt,
    String requestedRevision,
    String jenkinsBuildUrl
) {
    if (!(checkRunId ==~ /[0-9]{1,30}/) ||
        !(headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/) ||
        !(conclusion in ['success', 'failure', 'cancelled']) ||
        !(appId ==~ /[0-9]{1,20}/)) {
        throw new IllegalArgumentException('The trusted E2E publisher received invalid completion metadata.')
    }
    def credential = com.cloudbees.plugins.credentials.CredentialsProvider.findCredentialById(
        credentialId,
        org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials.class,
        run,
        java.util.Collections.emptyList()
    )
    if (credential == null) {
        throw new IllegalStateException('The controller could not resolve the configured GitHub App credential.')
    }
    String installationToken = credential.getPassword()?.getPlainText()
    if (!installationToken) {
        throw new IllegalStateException('The configured GitHub App credential did not provide an installation token.')
    }

    String endpoint = "https://api.github.com/repos/${owner}/${repository}/check-runs/${checkRunId}"
    Map response = githubChecksRequest('PATCH', endpoint, installationToken, [
        name: 'jenkins-e2e',
        status: 'completed',
        conclusion: conclusion,
        completed_at: completedAt,
        details_url: detailsUrl,
        output: [
            title: "Playwright E2E: ${conclusion.toUpperCase()}",
            summary: "Scheduled/manual Playwright verification ${conclusion} on exact commit ${headSha.toLowerCase()}.",
            text: "Verified commit SHA: ${headSha.toLowerCase()}\nRequested revision: ${requestedRevision}\nSuites: standard Playwright E2E, finance fail-closed, and AI skills pack.\nJenkins build: ${jenkinsBuildUrl ?: 'local Jenkins build'}"
        ]
    ], 200)

    if (response.name != 'jenkins-e2e' ||
        response.head_sha?.toString()?.equalsIgnoreCase(headSha) != true ||
        response.app?.id?.toString() != appId ||
        response.status != 'completed' ||
        response.conclusion != conclusion) {
        throw new IllegalStateException('GitHub did not confirm the expected completed E2E check, App attribution, and commit SHA.')
    }
}

pipeline {
    agent none

    options {
        timeout(time: 120, unit: 'MINUTES')
        disableConcurrentBuilds(abortPrevious: true)
        skipDefaultCheckout(true)
    }

    parameters {
        string(name: 'TARGET_SHA', defaultValue: 'main', description: 'Use main for the nightly run or a full commit SHA for a manual run.')
    }

    stages {
        stage('Validate target') {
            steps {
                script {
                    def requestedRevision = (params.TARGET_SHA ?: 'main').trim()
                    if (requestedRevision != 'main' && !(requestedRevision ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
                        error('TARGET_SHA must be main or a complete Git commit SHA.')
                    }
                    env.JENKINS_E2E_REQUESTED_REVISION = requestedRevision.toLowerCase()
                }
            }
        }

        stage('Playwright E2E') {
            agent {
                label 'setness-e2e-ephemeral'
            }
            steps {
                script {
                    deleteDir()
                    try {
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: env.JENKINS_E2E_REQUESTED_REVISION == 'main'
                                ? '*/main'
                                : env.JENKINS_E2E_REQUESTED_REVISION]],
                            doGenerateSubmoduleConfigurations: false,
                            extensions: [
                                [$class: 'CleanBeforeCheckout'],
                                [$class: 'CloneOption', depth: 1, noTags: true, shallow: true, timeout: 10]
                            ],
                            userRemoteConfigs: [[
                                credentialsId: checkoutCredentialId,
                                url: repositoryUrl
                            ]]
                        ])

                        def checkedOutSha = sh(returnStdout: true, script: 'git rev-parse HEAD').trim().toLowerCase()
                        if (!(checkedOutSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/) ||
                            (env.JENKINS_E2E_REQUESTED_REVISION != 'main' && checkedOutSha != env.JENKINS_E2E_REQUESTED_REVISION)) {
                            error('The E2E checkout did not resolve to the requested commit; no tests ran.')
                        }
                        echo "E2E target commit: ${checkedOutSha}"
                        env.JENKINS_E2E_CHECKED_OUT_SHA = checkedOutSha

                        def startedAt = java.time.Instant.now().toString()
                        def check = createE2eCheck(
                            currentBuild.rawBuild,
                            appCredentialId,
                            targetOwner,
                            targetRepository,
                            expectedAppId,
                            checkedOutSha,
                            "${checkDetailsBase}${checkedOutSha}/checks",
                            startedAt
                        )
                        env.JENKINS_E2E_CHECK_RUN_ID = check.id
                        env.JENKINS_E2E_CHECK_STARTED_AT = startedAt
                        if (check.name != 'jenkins-e2e' ||
                            !check.headSha.equalsIgnoreCase(checkedOutSha) ||
                            check.appId != expectedAppId) {
                            error('GitHub did not confirm the expected E2E check App attribution and exact commit SHA.')
                        }

                        dir(appDirectory) {
                            sh '''#!/usr/bin/env bash
set -euo pipefail
test "$(node --version)" = "v22.23.3"
test "$(npx playwright --version)" = "Version 1.62.1"
test -d "$PLAYWRIGHT_BROWSERS_PATH"
npm ci
npm run test:e2e
npm run test:e2e:finance-gpt-fail-closed
npx playwright test e2e/ai-skills-pack.spec.ts
'''
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
                def checkedOutSha = env.JENKINS_E2E_CHECKED_OUT_SHA ?: ''
                if (!(checkedOutSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
                    echo 'E2E check not published: the job did not verify an exact repository commit.'
                    return
                }

                def finalResult = currentBuild.currentResult ?: 'FAILURE'
                def conclusion = finalResult == 'SUCCESS'
                    ? 'success'
                    : finalResult == 'ABORTED' ? 'cancelled' : 'failure'
                try {
                    def checkRunId = env.JENKINS_E2E_CHECK_RUN_ID ?: ''
                    if (!(checkRunId ==~ /[0-9]{1,30}/)) {
                        error('The jenkins-e2e check was not created; no completion update can be published.')
                    }
                    completeE2eCheck(
                        currentBuild.rawBuild,
                        appCredentialId,
                        targetOwner,
                        targetRepository,
                        expectedAppId,
                        checkRunId,
                        checkedOutSha,
                        "${checkDetailsBase}${checkedOutSha}/checks",
                        conclusion,
                        java.time.Instant.now().toString(),
                        env.JENKINS_E2E_REQUESTED_REVISION ?: 'unknown',
                        env.BUILD_URL ?: ''
                    )
                } catch (publicationError) {
                    currentBuild.result = 'FAILURE'
                    echo 'Could not complete the explicit exact-SHA jenkins-e2e check. No credential or raw API response was logged.'
                }
            }
        }
    }
}
