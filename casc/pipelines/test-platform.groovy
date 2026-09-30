// Trusted Jenkins stage fragment for Test Platform execution contracts (API-390).
//
// This file is centrally maintained controller configuration. It is installed
// as an inline Pipeline script by casc/jobs.groovy exactly like the other
// trusted pipelines, so a target pull request can never supply or replace it.
//
// The fragment does four things, in this order:
//
//   1. resolve the approved execution request on the controller, failing closed
//      before any checkout or repository command runs;
//   2. run each approved suite with the Jenkins-owned command tokens, with no
//      shell interpolation of any repository-controlled value;
//   3. finalize one normalized receipt submission;
//   4. record the submission at a Jenkins-controlled evidence path.
//
// The adapter, not this fragment, owns the outcome vocabulary and the receipt
// identity. Test Platform owns the result mapping the adapter applies and
// re-derives every receipt again on ingestion, so a forged receipt fails.

String testPlatformQuote(String value) {
    if (value == null) {
        return null
    }
    return "'" + value.replace("'", "'\\''") + "'"
}

String testPlatformAdapterCommand(List<String> arguments) {
    def nodeBinary = System.getenv('JENKINS_TEST_PLATFORM_NODE')?.trim()
    def adapterRoot = System.getenv('JENKINS_TEST_PLATFORM_ADAPTER_ROOT')?.trim()
    if (!nodeBinary || !adapterRoot) {
        return null
    }
    def parts = [nodeBinary, "${adapterRoot}/src/cli.mjs".toString()]
    parts.addAll(arguments)
    return parts.collect { token -> testPlatformQuote(token) }.join(' ')
}

String testPlatformSuiteScript(Map entry) {
    // entry.command_tokens is a static, Jenkins-owned argv produced by the
    // approved catalog. No repository, plan, or pull-request value is
    // interpolated into the shell; tokens are re-quoted defensively anyway.
    def tokens = entry.command_tokens.collect { token -> testPlatformQuote(token?.toString()) }
    return 'set -euo pipefail\n' +
        "cd -- ${testPlatformQuote(entry.workspace?.toString())}\n" +
        "exec ${tokens.join(' ')}\n"
}

boolean testPlatformAgentClassAllowed(String agentClass) {
    // These are the only agent classes exposed by the centrally approved
    // Test Platform catalog. The resolved suite, not this pipeline stage,
    // chooses among them.
    return ['setness-ephemeral', 'setness-node24-ephemeral', 'setness-e2e-ephemeral'].contains(agentClass)
}

Map testPlatformNormalizedOutcome(String status, int exitCode, boolean timedOut, boolean cancelled) {
    if (cancelled) {
        return [status: 'cancelled', exitCode: exitCode]
    }
    if (timedOut) {
        return [status: 'timed-out', exitCode: exitCode]
    }
    if (status == null) {
        // Suite ran to completion without an explicit adapter status; derive from exitCode.
        return [status: (exitCode == 0 ? 'passed' : 'failed'), exitCode: exitCode]
    }
    return [status: status, exitCode: exitCode]
}

Map testPlatformSuiteResult(Map entry, String status, String observedSha, String repository) {
    return [
        suite_id: entry.suite_id,
        executor_id: entry.executor_id,
        status: status,
        observed_repository: repository,
        observed_sha: observedSha,
        passed_tests: 0,
        failed_tests: 0,
        skipped_tests: 0,
        duration_seconds: 0,
        artifacts: [],
        tool_versions: []
    ]
}

@NonCPS
Object testPlatformParseJson(String text) {
    // JsonSlurperClassic must not remain on the CPS stack (NotSerializableException).
    return new groovy.json.JsonSlurperClassic().parseText(text)
}

pipeline {
    agent none

    options {
        timeout(time: 180, unit: 'MINUTES')
        disableConcurrentBuilds(abortPrevious: true)
        skipDefaultCheckout(true)
    }

    stages {
        stage('Authorize and resolve Test Platform contract') {
            agent {
                label 'built-in'
            }
            steps {
                script {
                    env.TEST_PLATFORM_STATE = 'UNCLASSIFIED'

                    def requestPath = env.TEST_PLATFORM_EXECUTION_REQUEST?.trim()
                    def resolvedPath = env.TEST_PLATFORM_RESOLUTION_PATH?.trim()
                    def resultsPath = env.TEST_PLATFORM_RESULTS_PATH?.trim()
                    def submissionPath = env.TEST_PLATFORM_SUBMISSION_PATH?.trim()
                    if (!requestPath || !resolvedPath || !resultsPath || !submissionPath) {
                        error('Test Platform contract configuration is incomplete; no checkout or repository command was run.')
                    }
                    def verifyCommand = testPlatformAdapterCommand(['verify', requestPath])
                    if (verifyCommand == null) {
                        error('The trusted Test Platform adapter is not configured on this controller; no repository code was run.')
                    }

                    def verifiedText = sh(returnStdout: true, script: "set -euo pipefail\n${verifyCommand}\n")
                    def resolution = testPlatformParseJson(verifiedText.trim())
                    def planSha = resolution?.sha?.toString()
                    if (!(planSha ==~ /(?i)[0-9a-f]{40}|[0-9a-f]{64}/)) {
                        error('The trusted adapter did not return a valid exact plan SHA; no repository code was run.')
                    }

                    // A pull-request build must agree with the controller-verified
                    // PR head that the trusted pilot already established.
                    def verifiedHeadSha = env.JENKINS_PILOT_PR_HEAD_SHA?.trim()
                    if (verifiedHeadSha && !planSha.equalsIgnoreCase(verifiedHeadSha)) {
                        error('The Test Platform plan does not bind the controller-verified pull request head SHA; no repository code was run.')
                    }

                    if (!(resolution?.resolved instanceof List) || resolution.resolved.isEmpty()) {
                        error('The trusted adapter resolved no approved suites; no repository code was run.')
                    }
                    writeFile file: resolvedPath, text: groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(resolution))
                    stash name: 'test-platform-resolution', includes: "${resolvedPath}"
                    env.TEST_PLATFORM_STATE = 'AUTHORIZED'
                    echo "Test Platform contract ${resolution.contract_id}@${resolution.contract_version} resolved ${resolution.resolved.size()} approved suite(s) for ${resolution.repository}@${planSha}."
                }
            }
        }

        stage('Execute approved Test Platform suites') {
            agent {
                // This stage only orchestrates trusted suite selection and
                // result collection. Each repository checkout and command
                // runs inside node(entry.agent_class) below.
                label 'built-in'
            }
            steps {
                script {
                    if (env.TEST_PLATFORM_STATE != 'AUTHORIZED') {
                        error('The Test Platform contract was not authorized on the controller; no repository code was run.')
                    }
                    unstash 'test-platform-resolution'
                    def resolution = testPlatformParseJson(readFile(env.TEST_PLATFORM_RESOLUTION_PATH))
                    def results = []
                    def infrastructureFailure = null
                    try {
                        resolution.resolved.each { entry ->
                            def suiteId = entry.suite_id
                            def agentClass = entry.agent_class?.toString()
                            def status = 'malformed-result'
                            def exitCode = -1
                            def timedOut = false
                            def cancelled = false
                            def agentAllocated = false
                            def checkoutComplete = false
                            def cleanupSucceeded = false
                            def observedSha = resolution.sha?.toString()?.toLowerCase() ?: ''
                            if (!testPlatformAgentClassAllowed(agentClass)) {
                                status = 'agent-unavailable'
                                echo "Test Platform suite ${suiteId} resolved to an unapproved agent class; no repository code ran."
                            } else {
                                try {
                                    timeout(time: entry.timeout_seconds, unit: 'SECONDS') {
                                        node(agentClass) {
                                            agentAllocated = true
                                            try {
                                                deleteDir()
                                                // The repository identity is centrally approved and the
                                                // SHA is the controller-verified plan binding, so the
                                                // checkout target is never repository-controlled.
                                                checkout([
                                                    $class: 'GitSCM',
                                                    branches: [[name: resolution.sha]],
                                                    doGenerateSubmoduleConfigurations: false,
                                                    extensions: [
                                                        [$class: 'CleanBeforeCheckout'],
                                                        [$class: 'CloneOption', depth: 1, noTags: true, shallow: true, timeout: 10]
                                                    ],
                                                    userRemoteConfigs: [[
                                                        credentialsId: env.JENKINS_CHECKOUT_SSH_CREDENTIAL_ID,
                                                        url: "git@github.com:${resolution.repository}.git"
                                                    ]]
                                                ])
                                                def checkedOutSha = sh(
                                                    returnStdout: true,
                                                    script: 'git rev-parse HEAD'
                                                ).trim().toLowerCase()
                                                if (checkedOutSha != resolution.sha.toLowerCase()) {
                                                    error('The Test Platform checkout did not resolve to the bound exact SHA; no tests ran.')
                                                }
                                                // Custom GitSCM checkout does not populate GIT_COMMIT; bind it
                                                // from the verified checkout so observed_sha is never empty.
                                                env.GIT_COMMIT = checkedOutSha
                                                observedSha = checkedOutSha
                                                checkoutComplete = true
                                                status = null
                                                exitCode = sh(
                                                    returnStatus: true,
                                                    script: testPlatformSuiteScript(entry)
                                                )
                                            } finally {
                                                deleteDir()
                                                cleanupSucceeded = true
                                            }
                                        }
                                    }
                                } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException interrupted) {
                                    cancelled = currentBuild.currentResult == 'ABORTED'
                                    timedOut = !cancelled
                                    echo "Test Platform suite ${suiteId} did not complete; the normalized outcome records the interruption rather than a pass."
                                } catch (Exception suiteFailure) {
                                    if (!agentAllocated) {
                                        status = 'agent-unavailable'
                                    } else if (!checkoutComplete) {
                                        status = 'checkout-sha-mismatch'
                                    } else if (!cleanupSucceeded) {
                                        status = 'failed'
                                        exitCode = 1
                                    }
                                    echo "Test Platform suite ${suiteId} did not complete cleanly; the normalized outcome records the failure rather than a pass."
                                }
                            }

                            def outcome = testPlatformNormalizedOutcome(status, exitCode, timedOut, cancelled)
                            results << [
                                suite_id: suiteId,
                                executor_id: entry.executor_id,
                                status: outcome.status ?: 'malformed-result',
                                observed_repository: resolution.repository,
                                observed_sha: observedSha,
                                passed_tests: 0,
                                failed_tests: 0,
                                skipped_tests: 0,
                                duration_seconds: 0,
                                artifacts: [],
                                tool_versions: []
                            ]
                        }
                    } catch (Exception executionFailure) {
                        infrastructureFailure = executionFailure
                        echo "Test Platform execution could not run every approved suite; unreported suites are recorded as agent-unavailable."
                    }

                    // An infrastructure failure never becomes a pass: every
                    // planned suite that did not report a normalized outcome is
                    // agent-unavailable, which the contract normalizes to BLOCKED.
                    if (infrastructureFailure != null) {
                        def reported = results.collect { result -> result.suite_id }
                        resolution.resolved.each { entry ->
                            if (!reported.contains(entry.suite_id)) {
                                results << testPlatformSuiteResult(entry, 'agent-unavailable', (env.GIT_COMMIT ?: resolution.sha ?: ''), resolution.repository)
                            }
                        }
                    }

                    writeFile file: env.TEST_PLATFORM_RESULTS_PATH, text: groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(results))
                    stash name: 'test-platform-results', includes: "${env.TEST_PLATFORM_RESULTS_PATH}"
                }
            }
        }

        stage('Finalize Test Platform receipts') {
            agent {
                label 'built-in'
            }
            steps {
                script {
                    unstash 'test-platform-results'
                    def finalizeCommand = testPlatformAdapterCommand([
                        'finalize',
                        env.TEST_PLATFORM_EXECUTION_REQUEST,
                        env.TEST_PLATFORM_RESULTS_PATH,
                        env.TEST_PLATFORM_SUBMISSION_PATH
                    ])
                    if (finalizeCommand == null) {
                        error('The trusted Test Platform adapter is not configured on this controller.')
                    }
                    def finalized = sh(returnStdout: true, script: "set -euo pipefail\n${finalizeCommand}\n")
                    def summary = testPlatformParseJson(finalized.trim())
                    echo "Test Platform submission accepted: ${summary.outcomes} normalized receipt(s)."
                    if (!env.TEST_PLATFORM_EVIDENCE_ROOT) {
                        echo 'No Test Platform evidence root is configured; the normalized submission is not published.'
                        return
                    }
                    archiveArtifacts artifacts: "${env.TEST_PLATFORM_SUBMISSION_PATH}", fingerprint: true, allowEmptyArchive: false
                }
            }
        }
    }

    post {
        always {
            script {
                if (env.TEST_PLATFORM_STATE != 'AUTHORIZED') {
                    currentBuild.result = 'FAILURE'
                    echo 'The Test Platform contract failed closed before any checkout; no repository code was run and no receipt was published.'
                }
            }
        }
    }
}
