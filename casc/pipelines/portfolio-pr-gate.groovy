// Centrally trusted, manual-only entry point for portfolio PR shadow checks.
// No repository-provided Pipeline is loaded or executed.
def portfolioAppCredentialId = /* JENKINS_PORTFOLIO_APP_CREDENTIAL_ID */
def portfolioCatalogRepository = /* JENKINS_PORTFOLIO_CATALOG_REPOSITORY */
def portfolioCatalogPath = 'profiles/profiles.json'
def portfolioNodeBinary = '/opt/setness-jenkins/tools/node-v22.23.3-linux-x64/bin/node'
def portfolioResolver = '/usr/share/jenkins/portfolio-profile-contract/src/resolve-pr.mjs'
def portfolioAdapterImplementationAllowlist = [
    'setness-web-ci-node22-v1',
    'node22-foundation-v1', 'node22-verify-clean-checkout-v1',
    'jenkins-repository-contract',
    'python312-test-platform-v1', 'python312-playtest-lab-v1', 'python312-cloudflare-api-uv-v1',
    'python312-jira-admin-uv-v1',
    'python312-blender-api-v1', 'python312-fmod-api-v1', 'python312-game-maker-v1',
    'python312-context-file-maker-v1', 'python312-cpa-ai-pack-v1',
    'node2214-vercel-api-gitleaks-v1', 'node2214-unity-api-maintenance-v1',
    'node22-github-api-foundation-v1', 'node22-investment-council-v1',
    'node22-supabase-api-v1',
    'node24-game-platform-sdk-v1', 'node24-game-planetary-survey-v1',
    'node24-game-fraction-match-full-ci-v1',
    'node24-curiouspathway-pilot-v1', 'python312-portfolio-graph-uv-v1'
]
/* JENKINS_PORTFOLIO_CREDENTIAL_STORE_HELPERS */

@com.cloudbees.groovy.cps.NonCPS
boolean portfolioHasProvisionableConfiguredAgentClass(String agentClass) {
    if (!(agentClass ==~ /[A-Za-z0-9._-]{1,100}/)) return false
    def jenkins = jenkins.model.Jenkins.get()
    def label = jenkins.getLabelAtom(agentClass)
    if (label == null) return false
    return jenkins.clouds.any { cloud ->
        cloud instanceof com.nirima.jenkins.plugins.docker.DockerCloud &&
            cloud.canProvision(label) &&
            cloud.getTemplates().any { template ->
                !template.getDisabled().isDisabled() && label.matches(template.getLabelSet())
            }
    }
}

@com.cloudbees.groovy.cps.NonCPS
String portfolioScopedAppToken(def run, String credentialId, String repository, Map permissions) {
    def read = org.kohsuke.github.GHPermissionType.READ
    def write = org.kohsuke.github.GHPermissionType.WRITE
    def permittedScopes = [
        [contents: read],
        [pull_requests: read],
        [checks: write]
    ]
    if (!(repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
        !(permissions in permittedScopes)) {
        throw new IllegalArgumentException('The controller requested an unsupported repository or App permission scope.')
    }
    def baseCredential = com.cloudbees.plugins.credentials.CredentialsProvider.findCredentialById(
        credentialId,
        org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials.class,
        run,
        java.util.Collections.emptyList()
    )
    if (baseCredential == null) {
        throw new IllegalStateException('The controller could not resolve the configured GitHub App credential.')
    }

    String[] parts = repository.split('/', 2)
    def scopedCredential = new org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials(
        com.cloudbees.plugins.credentials.CredentialsScope.GLOBAL,
        'portfolio-temporary-token',
        'Ephemeral repository-scoped portfolio API token',
        baseCredential.getAppID(),
        baseCredential.getPrivateKey()
    )
    if (baseCredential.getApiUri()) {
        scopedCredential.setApiUri(baseCredential.getApiUri())
    }
    scopedCredential.setRepositoryAccessStrategy(
        new org.jenkinsci.plugins.github_branch_source.app_credentials.AccessSpecifiedRepositories(parts[0], [parts[1]])
    )
    def usageContext = org.jenkinsci.plugins.github_branch_source.GitHubAppUsageContext.builder()
        .inferredOwner(parts[0])
        .inferredRepository(parts[1])
        .permissions(permissions)
        .build()
    String token = scopedCredential.contextualize(usageContext).getPassword()?.getPlainText()
    if (!token) {
        throw new IllegalStateException('The controller could not mint a repository-scoped GitHub App token.')
    }
    return token
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioApiRequest(String method, String path, String token, Map payload, int expectedStatus) {
    if (!(method in ['GET', 'POST', 'PATCH']) || !path.startsWith('/repos/setnessconsulting/') ||
        path.contains('..') || !token || !(expectedStatus in [200, 201])) {
        throw new IllegalArgumentException('The controller API request did not match its fixed GitHub boundary.')
    }
    int responseStatus = -1
    try {
        def builder = java.net.http.HttpRequest.newBuilder(java.net.URI.create("https://api.github.com${path}"))
            .timeout(java.time.Duration.ofSeconds(20))
            .header('Accept', 'application/vnd.github+json')
            .header('Authorization', "Bearer ${token}")
            .header('X-GitHub-Api-Version', '2022-11-28')
            .header('Content-Type', 'application/json; charset=utf-8')
        def body = payload == null
            ? java.net.http.HttpRequest.BodyPublishers.noBody()
            : java.net.http.HttpRequest.BodyPublishers.ofString(
                groovy.json.JsonOutput.toJson(payload),
                java.nio.charset.StandardCharsets.UTF_8
            )
        def request = builder.method(method, body).build()
        def client = java.net.http.HttpClient.newBuilder()
            .connectTimeout(java.time.Duration.ofSeconds(10))
            .build()
        def response = client.send(
            request,
            java.net.http.HttpResponse.BodyHandlers.ofString(java.nio.charset.StandardCharsets.UTF_8)
        )
        responseStatus = response.statusCode()
        if (responseStatus != expectedStatus ||
            response.body().getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 1024 * 1024) {
            throw new IllegalStateException('GitHub returned an unexpected status or oversized controller response.')
        }
        return (Map) new groovy.json.JsonSlurperClassic().parseText(response.body())
    } catch (InterruptedException interrupted) {
        Thread.currentThread().interrupt()
        throw new IllegalStateException('The controller GitHub API request was interrupted.')
    } catch (Exception ignored) {
        String statusHint = responseStatus >= 0 ? " (HTTP ${responseStatus})" : ''
        throw new IllegalStateException("The controller GitHub API request failed${statusHint}; no credential or raw response was logged.")
    }
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioRepoApiRequest(
    def run,
    String credentialId,
    String repository,
    Map permissions,
    String method,
    String path,
    Map payload,
    int expectedStatus
) {
    String token = portfolioScopedAppToken(run, credentialId, repository, permissions)
    try {
        return portfolioApiRequest(method, path, token, payload, expectedStatus)
    } finally {
        token = null
    }
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioFetchJsonFile(def run, String credentialId, String repository, String path, String ref) {
    if (!(repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
        !(path ==~ /[A-Za-z0-9._\/-]{1,200}/) || path.startsWith('/') ||
        path.split('/').any { it in ['.', '..'] } ||
        !(ref ==~ /(?i)[0-9a-f]{40}|[0-9a-f]{64}/)) {
        throw new IllegalArgumentException('The controller catalog reference is not a pinned repository file.')
    }
    String token = portfolioScopedAppToken(run, credentialId, repository, [contents: org.kohsuke.github.GHPermissionType.READ])
    String encodedPath = path.split('/').collect { java.net.URLEncoder.encode(it, 'UTF-8') }.join('/')
    String encodedRef = java.net.URLEncoder.encode(ref, 'UTF-8')
    Map response = portfolioApiRequest('GET', "/repos/${repository}/contents/${encodedPath}?ref=${encodedRef}", token, null, 200)
    if (response.type != 'file' || response.encoding != 'base64' || !(response.content instanceof String)) {
        throw new IllegalStateException('The private catalog response was not a base64 file object.')
    }
    byte[] decoded = java.util.Base64.getDecoder().decode(response.content.replaceAll('\\s', ''))
    if (decoded.length > 1024 * 1024) {
        throw new IllegalStateException('The private catalog exceeded the controller input limit.')
    }
    String catalogText = new String(decoded, java.nio.charset.StandardCharsets.UTF_8)
    return [catalog: (Map) new groovy.json.JsonSlurperClassic().parseText(catalogText)]
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioResolveProfile(String nodeBinary, String adapterPath, Map envelope) {
    byte[] requestBytes = groovy.json.JsonOutput.toJson(envelope).getBytes(java.nio.charset.StandardCharsets.UTF_8)
    if (requestBytes.length == 0 || requestBytes.length > 1024 * 1024) {
        throw new IllegalArgumentException('The controller profile envelope is empty or exceeds its size limit.')
    }
    Process process = null
    try {
        process = new ProcessBuilder(nodeBinary, adapterPath).start()
        process.outputStream.withCloseable { stream -> stream.write(requestBytes) }
        if (!process.waitFor(30, java.util.concurrent.TimeUnit.SECONDS)) {
            process.destroyForcibly()
            throw new IllegalStateException('The trusted portfolio resolver exceeded its controller time limit.')
        }
        String output = process.inputStream.getText('UTF-8')
        String errorOutput = process.errorStream.getText('UTF-8')
        if (output.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 65536 ||
            errorOutput.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 4096) {
            throw new IllegalStateException('The trusted portfolio resolver returned oversized output.')
        }
        if (process.exitValue() != 0) {
            Map rejection = errorOutput ? (Map) new groovy.json.JsonSlurperClassic().parseText(errorOutput.trim()) : [:]
            String code = rejection?.code?.toString()
            if (!(code ==~ /[a-z0-9-]{1,64}/)) code = 'profile-rejected'
            throw new IllegalStateException("The portfolio profile was rejected before checkout (${code}).")
        }
        Map result = (Map) new groovy.json.JsonSlurperClassic().parseText(output.trim())
        if (result.status != 'accepted' || !(result.plan instanceof Map)) {
            throw new IllegalStateException('The trusted portfolio resolver returned an invalid execution plan.')
        }
        return result.plan
    } catch (InterruptedException interrupted) {
        Thread.currentThread().interrupt()
        throw new IllegalStateException('The trusted portfolio resolver was interrupted.')
    } catch (Exception ignored) {
        if (ignored instanceof IllegalStateException && ignored.message?.startsWith('The portfolio profile was rejected')) {
            throw ignored
        }
        throw new IllegalStateException('The controller could not run the trusted portfolio resolver.')
    } finally {
        if (process != null && process.isAlive()) process.destroyForcibly()
        java.util.Arrays.fill(requestBytes, (byte) 0)
    }
}

@com.cloudbees.groovy.cps.NonCPS
String portfolioCreateCheckoutCredential(def run, String appCredentialId, String repository) {
    String token = portfolioScopedAppToken(
        run,
        appCredentialId,
        repository,
        [contents: org.kohsuke.github.GHPermissionType.READ]
    )
    String credentialId = "portfolio-checkout-${java.util.UUID.randomUUID().toString()}"
    def credential = null
    def store = null
    try {
        credential = new com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl(
            com.cloudbees.plugins.credentials.CredentialsScope.GLOBAL,
            credentialId,
            "Portfolio checkout token temporary; created=${java.time.Instant.now().toEpochMilli()}; one repo only",
            'x-access-token',
            token
        )
        store = portfolioFolderCredentialStore(run)
        def domain = com.cloudbees.plugins.credentials.domains.Domain.global()
        def existing = store.getCredentials(domain).find { it.id == credentialId }
        if (existing != null) {
            throw new IllegalStateException('The generated temporary checkout credential ID already exists.')
        }
        if (!store.addCredentials(domain, credential)) {
            throw new IllegalStateException('The folder credential store refused the temporary checkout credential.')
        }
        store.save()
        return credentialId
    } catch (Exception ignored) {
        try {
            if (store != null) {
                def domain = com.cloudbees.plugins.credentials.domains.Domain.global()
                def partial = store.getCredentials(domain).find { it.id == credentialId }
                if (partial != null) {
                    if (!partial.is(credential) ||
                        !store.removeCredentials(domain, partial)) {
                        throw new IllegalStateException('The partial credential could not be safely identified or removed.')
                    }
                }
                store.save()
            }
        } catch (Exception cleanupFailure) {
            throw new IllegalStateException('Temporary checkout credential setup failed and rollback could not be confirmed; the token is limited to one repository, expires within one hour, and the scheduled reaper will retry cleanup.')
        }
        throw new IllegalStateException('The controller could not register the folder-scoped temporary checkout credential; any partial addition was rolled back.')
    } finally {
        token = null
        credential = null
        store = null
    }
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioGithubCheckRequest(
    def run,
    String appCredentialId,
    String repository,
    String method,
    String path,
    Map payload,
    int expectedStatus
) {
    String token = portfolioScopedAppToken(
        run,
        appCredentialId,
        repository,
        [checks: org.kohsuke.github.GHPermissionType.WRITE]
    )
    return portfolioApiRequest(method, path, token, payload, expectedStatus)
}

@com.cloudbees.groovy.cps.NonCPS
String portfolioDispatchIdForRun(def run) {
    String dispatchId = run.getAction(hudson.model.ParametersAction.class)
        ?.getParameter('PORTFOLIO_DISPATCH_ID')?.value?.toString()?.trim() ?: ''
    if (!dispatchId) return ''
    if (!(dispatchId ==~ /(?i)[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/)) {
        throw new IllegalArgumentException('The controller poll dispatch identity is invalid.')
    }
    def upstreamCause = run.getCause(hudson.model.Cause.UpstreamCause.class)
    if (upstreamCause?.getUpstreamProject() != 'portfolio-dispatch/portfolio-pr-poller') {
        throw new IllegalArgumentException('Only the trusted portfolio poller may set a dispatch identity.')
    }
    return dispatchId.toLowerCase()
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioCreateCheck(def run, String appCredentialId, String repository, String headSha) {
    if (!(repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
        !(headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
        throw new IllegalArgumentException('The controller check target is invalid.')
    }
    String dispatchId = portfolioDispatchIdForRun(run)
    String externalId = "jenkins:${run.getExternalizableId()}" +
        (dispatchId ? ";portfolio-dispatch:${dispatchId.toLowerCase()}" : '')
    String detailsUrl = "https://github.com/${repository}/commit/${headSha}/checks"
    Map response = portfolioGithubCheckRequest(run, appCredentialId, repository, 'POST', "/repos/${repository}/check-runs", [
        name: 'jenkins-pr-gate',
        head_sha: headSha.toLowerCase(),
        status: 'in_progress',
        started_at: java.time.Instant.now().toString(),
        details_url: detailsUrl,
        external_id: externalId,
        output: [
            title: 'Portfolio Jenkins verification: RUNNING',
            summary: "Centrally trusted verification started on exact PR head ${headSha.toLowerCase()}.",
            text: 'Profile selection and commands are centrally controlled; Actions remains authoritative during shadow qualification.'
        ]
    ], 201)
    String expectedAppId = com.cloudbees.plugins.credentials.CredentialsProvider.findCredentialById(
        appCredentialId,
        org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials.class,
        run,
        java.util.Collections.emptyList()
    )?.getAppID()?.toString()
    if (!(response.id instanceof Number) || response.name != 'jenkins-pr-gate' ||
        response.head_sha?.toString()?.equalsIgnoreCase(headSha) != true ||
        response.app?.id?.toString() != expectedAppId || response.status != 'in_progress') {
        throw new IllegalStateException('GitHub did not confirm the expected App, check name, and exact head SHA.')
    }
    return [id: response.id.toString(), headSha: response.head_sha.toString(), appId: expectedAppId]
}

@com.cloudbees.groovy.cps.NonCPS
void portfolioCompleteCheck(
    def run,
    String appCredentialId,
    String repository,
    String checkId,
    String headSha,
    String conclusion
) {
    if (!(repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
        !(checkId ==~ /[0-9]{1,30}/) || !(headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/) ||
        !(conclusion in ['success', 'failure', 'cancelled'])) {
        throw new IllegalArgumentException('The controller check completion metadata is invalid.')
    }
    String detailsUrl = "https://github.com/${repository}/commit/${headSha}/checks"
    Map response = portfolioGithubCheckRequest(run, appCredentialId, repository, 'PATCH',
        "/repos/${repository}/check-runs/${checkId}", [
            name: 'jenkins-pr-gate',
            status: 'completed',
            conclusion: conclusion,
            completed_at: java.time.Instant.now().toString(),
            details_url: detailsUrl,
            output: [
                title: "Portfolio Jenkins verification: ${conclusion.toUpperCase()}",
                summary: "Centrally trusted verification ${conclusion} on exact PR head ${headSha.toLowerCase()}.",
                text: "Verified repository: ${repository}\nVerified head SHA: ${headSha.toLowerCase()}\nActions remains authoritative until this repository's qualification and cutover gates pass."
            ]
        ], 200)
    String expectedAppId = com.cloudbees.plugins.credentials.CredentialsProvider.findCredentialById(
        appCredentialId,
        org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials.class,
        run,
        java.util.Collections.emptyList()
    )?.getAppID()?.toString()
    if (response.name != 'jenkins-pr-gate' || response.head_sha?.toString()?.equalsIgnoreCase(headSha) != true ||
        response.app?.id?.toString() != expectedAppId || response.status != 'completed' ||
        response.conclusion != conclusion) {
        throw new IllegalStateException('GitHub did not confirm the expected completed App check and exact head SHA.')
    }
}

String portfolioShellQuote(String value) {
    if (value == null || value.isEmpty()) {
        throw new IllegalArgumentException('The central profile returned an empty command token.')
    }
    return "'${value.replace("'", "'\\''")}'"
}

pipeline {
    agent none

    options {
        timeout(time: 90, unit: 'MINUTES')
        // Serialize portfolio dispatches without aborting an in-flight exact-SHA run.
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    stages {
        stage('Authorize exact PR and resolve profile on controller') {
            steps {
                script {
                    env.PORTFOLIO_STATE = 'UNCLASSIFIED'
                    env.PORTFOLIO_CHECK_RUN_ID = ''
                    portfolioCleanupStaleCheckoutCredentials(currentBuild.rawBuild, 65 * 60 * 1000L)

                    String repository = params.TARGET_REPOSITORY?.trim()
                    String pullRequestNumberText = params.PULL_REQUEST_NUMBER?.trim()
                    String expectedSha = params.EXPECTED_HEAD_SHA?.trim()?.toLowerCase()
                    String dispatchId = portfolioDispatchIdForRun(currentBuild.rawBuild)
                    if (!(repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
                        !(pullRequestNumberText ==~ /[1-9][0-9]{0,8}/) ||
                        !(expectedSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
                        error('Enter a valid Setness repository, PR number, and full head SHA; no checkout or repository command ran.')
                    }
                    int pullRequestNumber = Integer.parseInt(pullRequestNumberText)

                    Map pullRequest = portfolioRepoApiRequest(
                        currentBuild.rawBuild,
                        portfolioAppCredentialId,
                        repository,
                        [pull_requests: org.kohsuke.github.GHPermissionType.READ],
                        'GET',
                        "/repos/${repository}/pulls/${pullRequestNumber}",
                        null,
                        200
                    )
                    String currentHeadSha = pullRequest?.head?.sha?.toString()?.toLowerCase()
                    String headRepository = pullRequest?.head?.repo?.full_name?.toString()
                    String baseRepository = pullRequest?.base?.repo?.full_name?.toString()
                    if (pullRequest.number != pullRequestNumber || pullRequest.state != 'open' || pullRequest.draft != false ||
                        !headRepository?.equalsIgnoreCase(repository) || !baseRepository?.equalsIgnoreCase(repository)) {
                        error('The live PR is draft, closed, or not same-repository; no checkout or repository command ran.')
                    }

                    Map check = portfolioCreateCheck(currentBuild.rawBuild, portfolioAppCredentialId, repository, expectedSha)
                    env.PORTFOLIO_CHECK_RUN_ID = check.id
                    env.PORTFOLIO_HEAD_SHA = expectedSha
                    env.PORTFOLIO_REPOSITORY = repository
                    env.PORTFOLIO_STATE = 'CHECK_PENDING'

                    if (!currentHeadSha || currentHeadSha != expectedSha) {
                        error('The live PR head changed after dispatch; no checkout or repository command ran. Jenkins will finalize the exact requested SHA check as failed.')
                    }

                    if (!pullRequest.user?.login?.toString()?.equalsIgnoreCase('setnessconsulting')) {
                        error('The current owner-only shadow policy blocked this author before checkout; Jenkins will finalize the exact-SHA check as failed.')
                    }

                    Map catalogRef = portfolioRepoApiRequest(
                        currentBuild.rawBuild,
                        portfolioAppCredentialId,
                        portfolioCatalogRepository,
                        [contents: org.kohsuke.github.GHPermissionType.READ],
                        'GET',
                        "/repos/${portfolioCatalogRepository}/commits/main",
                        null,
                        200
                    )
                    String catalogCommitSha = catalogRef?.sha?.toString()?.toLowerCase()
                    if (!(catalogCommitSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
                        error('The controller could not resolve a full private-catalog main SHA; no checkout or repository command ran.')
                    }
                    Map catalogRead = portfolioFetchJsonFile(
                        currentBuild.rawBuild,
                        portfolioAppCredentialId,
                        portfolioCatalogRepository,
                        portfolioCatalogPath,
                        catalogCommitSha
                    )
                    Map catalog = catalogRead.catalog
                    Map profile = catalog?.profiles?.find { item ->
                        item?.repositories instanceof List && item.repositories.any { it?.toString()?.equalsIgnoreCase(repository) }
                    }
                    if (profile == null || !(profile.status in ['shadow', 'qualified']) ||
                        !(profile.implementationId in portfolioAdapterImplementationAllowlist)) {
                        error('This repository does not yet have an enabled profile in the manual portfolio shadow allowlist; no checkout or repository command ran.')
                    }

                    Map resolved = portfolioResolveProfile(portfolioNodeBinary, portfolioResolver, [
                        catalog: catalog,
                        pr: pullRequest,
                        request: [
                            repository: repository,
                            pullRequestNumber: pullRequestNumber,
                            headSha: expectedSha
                        ]
                    ])
                    boolean hasNodeRuntime = resolved.nodeVersion?.toString() ==~ /\d+\.\d+\.\d+/
                    boolean hasPythonRuntime = resolved.pythonVersion?.toString() ==~ /\d+\.\d+\.\d+/
                    boolean hasAdditionalPythonRuntime = resolved.additionalPythonVersion?.toString() ==~ /\d+\.\d+\.\d+/
                    boolean nodeRuntimeMatches = hasNodeRuntime &&
                        resolved.nodeVersion.toString() == profile.requiredNodeVersion?.toString() &&
                        profile.requiredPythonVersion == null
                    boolean pythonRuntimeMatches = hasPythonRuntime &&
                        resolved.pythonVersion.toString() == profile.requiredPythonVersion?.toString() &&
                        profile.requiredNodeVersion == null
                    String resolvedAgentClass = resolved.agentClass?.toString()
                    if (resolved.repository?.toString()?.equalsIgnoreCase(repository) != true ||
                        resolved.headSha?.toString()?.equalsIgnoreCase(expectedSha) != true ||
                        resolved.profileId?.toString() != profile.id.toString() ||
                        resolved.requiredCheck != 'jenkins-pr-gate' ||
                        hasNodeRuntime == hasPythonRuntime ||
                        !(nodeRuntimeMatches || pythonRuntimeMatches) ||
                        (resolved.additionalPythonVersion != null &&
                            (!hasAdditionalPythonRuntime || !pythonRuntimeMatches || resolvedAgentClass != 'setness-game-maker-python-matrix-ephemeral')) ||
                        (resolved.npmVersion != null && !(resolved.npmVersion.toString() ==~ /\d+\.\d+\.\d+/)) ||
                        !(resolvedAgentClass in ['setness-ephemeral', 'setness-node22-14-ephemeral', 'setness-node22-14-disposable-ephemeral', 'setness-web-ci-node22-ephemeral', 'setness-node24-ephemeral', 'setness-python312-ephemeral', 'setness-game-maker-python-matrix-ephemeral', 'secondary-node24-playwright-ephemeral']) ||
                        !(resolved.commands instanceof List) || resolved.commands.isEmpty()) {
                        error('The centrally trusted resolver returned a plan outside the controller contract; no checkout ran.')
                    }
                    if (!portfolioHasProvisionableConfiguredAgentClass(resolvedAgentClass)) {
                        error("No configured Jenkins cloud has an enabled template for the resolved agent class ${resolvedAgentClass}; the gate stopped before requesting a node or checking out the PR.")
                    }

                    env.PORTFOLIO_PROFILE_ID = profile.id.toString()
                    env.PORTFOLIO_AGENT_CLASS = resolvedAgentClass
                    env.PORTFOLIO_NODE_VERSION = resolved.nodeVersion?.toString() ?: ''
                    env.PORTFOLIO_PYTHON_VERSION = resolved.pythonVersion?.toString() ?: ''
                    env.PORTFOLIO_ADDITIONAL_PYTHON_VERSION = resolved.additionalPythonVersion?.toString() ?: ''
                    env.PORTFOLIO_NPM_VERSION = resolved.npmVersion?.toString() ?: ''
                    env.PORTFOLIO_COMMANDS_JSON = groovy.json.JsonOutput.toJson(resolved.commands)
                    env.PORTFOLIO_STATE = 'AUTHORIZED'
                    echo "Authorized central profile ${profile.id} for ${repository} PR #${pullRequestNumber} at exact head ${expectedSha}. No target Pipeline was loaded."
                }
            }
        }

        stage('Checkout exact PR head and run central commands') {
            steps {
                script {
                    if (env.PORTFOLIO_STATE != 'AUTHORIZED') {
                        error('The controller did not authorize a portfolio profile; no target code ran.')
                    }
                    def commands = new groovy.json.JsonSlurperClassic().parseText(env.PORTFOLIO_COMMANDS_JSON ?: '')
                    if (!(commands instanceof List) || commands.isEmpty() ||
                        commands.any { !(it instanceof List) || it.isEmpty() || it.any { token -> !(token instanceof String) } }) {
                        error('The controller command plan was malformed; no target code ran.')
                    }

                    node(env.PORTFOLIO_AGENT_CLASS) {
                        String temporaryCheckoutCredentialId = null
                        try {
                            deleteDir()
                            Map refreshedPullRequest = portfolioRepoApiRequest(
                                currentBuild.rawBuild,
                                portfolioAppCredentialId,
                                env.PORTFOLIO_REPOSITORY,
                                [pull_requests: org.kohsuke.github.GHPermissionType.READ],
                                'GET',
                                "/repos/${env.PORTFOLIO_REPOSITORY}/pulls/${params.PULL_REQUEST_NUMBER}",
                                null,
                                200
                            )
                            if (refreshedPullRequest.state != 'open' || refreshedPullRequest.draft != false ||
                                refreshedPullRequest.head?.sha?.toString()?.equalsIgnoreCase(env.PORTFOLIO_HEAD_SHA) != true ||
                                refreshedPullRequest.head?.repo?.full_name?.toString()?.equalsIgnoreCase(env.PORTFOLIO_REPOSITORY) != true ||
                                refreshedPullRequest.base?.repo?.full_name?.toString()?.equalsIgnoreCase(env.PORTFOLIO_REPOSITORY) != true ||
                                refreshedPullRequest.user?.login?.toString()?.equalsIgnoreCase('setnessconsulting') != true) {
                                error('The PR changed or no longer meets the same-repository shadow policy while waiting for an agent; no checkout occurred.')
                            }
                            temporaryCheckoutCredentialId = portfolioCreateCheckoutCredential(
                                currentBuild.rawBuild,
                                portfolioAppCredentialId,
                                env.PORTFOLIO_REPOSITORY
                            )
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: "refs/remotes/origin/pull/${params.PULL_REQUEST_NUMBER}/head"]],
                                doGenerateSubmoduleConfigurations: false,
                                extensions: [
                                    [$class: 'CleanBeforeCheckout'],
                                    [$class: 'CloneOption', depth: 1, noTags: true, shallow: true, honorRefspec: true, timeout: 10]
                                ],
                                userRemoteConfigs: [[
                                    credentialsId: temporaryCheckoutCredentialId,
                                    refspec: "+refs/pull/${params.PULL_REQUEST_NUMBER}/head:refs/remotes/origin/pull/${params.PULL_REQUEST_NUMBER}/head",
                                    url: "https://github.com/${env.PORTFOLIO_REPOSITORY}.git"
                                ]]
                            ])
                            String checkedOutSha = sh(returnStdout: true, script: 'git rev-parse HEAD').trim().toLowerCase()
                            if (checkedOutSha != env.PORTFOLIO_HEAD_SHA.toLowerCase()) {
                                error('Checkout did not match the controller-verified PR head SHA; no verification commands ran.')
                            }
                            portfolioRemoveCheckoutCredential(currentBuild.rawBuild, temporaryCheckoutCredentialId)
                            temporaryCheckoutCredentialId = null
                            List<String> runtimeEnvironment = []
                            if (env.PORTFOLIO_NODE_VERSION?.trim()) {
                                runtimeEnvironment.add("EXPECTED_NODE_VERSION=v${env.PORTFOLIO_NODE_VERSION}")
                                if (env.PORTFOLIO_NPM_VERSION?.trim()) {
                                    runtimeEnvironment.add("EXPECTED_NPM_VERSION=${env.PORTFOLIO_NPM_VERSION}")
                                }
                            } else if (env.PORTFOLIO_PYTHON_VERSION?.trim()) {
                                runtimeEnvironment.add("EXPECTED_PYTHON_VERSION=${env.PORTFOLIO_PYTHON_VERSION}")
                            }
                            if (env.PORTFOLIO_ADDITIONAL_PYTHON_VERSION?.trim()) {
                                runtimeEnvironment.add("EXPECTED_ADDITIONAL_PYTHON_VERSION=${env.PORTFOLIO_ADDITIONAL_PYTHON_VERSION}")
                            }
                            withEnv(runtimeEnvironment) {
                                sh '''#!/usr/bin/env bash
set -euo pipefail
if [ -n "${EXPECTED_NODE_VERSION:-}" ]; then
  test "$(node --version)" = "$EXPECTED_NODE_VERSION"
  if [ -n "${EXPECTED_NPM_VERSION:-}" ]; then
    test "$(npm --version)" = "$EXPECTED_NPM_VERSION"
  fi
elif [ -n "${EXPECTED_PYTHON_VERSION:-}" ]; then
  test "$(python --version)" = "Python $EXPECTED_PYTHON_VERSION"
else
  exit 1
fi
if [ -n "${EXPECTED_ADDITIONAL_PYTHON_VERSION:-}" ]; then
  test "$(python3.11 --version)" = "Python $EXPECTED_ADDITIONAL_PYTHON_VERSION"
fi
'''
                            }
                            commands.each { argv ->
                                String shellCommand = argv.collect { token -> portfolioShellQuote(token.toString()) }.join(' ')
                                int exitCode = sh(returnStatus: true, script: "set -euo pipefail\n${shellCommand}\n")
                                if (exitCode != 0) {
                                    error("The centrally approved profile command failed with exit code ${exitCode}.")
                                }
                            }
                        } finally {
                            try {
                                if (temporaryCheckoutCredentialId) {
                                    portfolioRemoveCheckoutCredential(currentBuild.rawBuild, temporaryCheckoutCredentialId)
                                }
                            } finally {
                                try {
                                    if (env.PORTFOLIO_PROFILE_ID == 'game-fraction-match-node24-full-ci') {
                                        archiveArtifacts artifacts: 'dist/**,coverage/coverage-summary.json,coverage/lcov.info,test-results/**,playwright-report/**,playwright-report-host/**',
                                            allowEmptyArchive: true,
                                            onlyIfSuccessful: false
                                    }
                                } finally {
                                    deleteDir()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                def checkId = env.PORTFOLIO_CHECK_RUN_ID?.trim()
                if (checkId) {
                    String conclusion = currentBuild.currentResult == 'SUCCESS'
                        ? 'success'
                        : currentBuild.currentResult == 'ABORTED' ? 'cancelled' : 'failure'
                    try {
                        portfolioCompleteCheck(
                            currentBuild.rawBuild,
                            portfolioAppCredentialId,
                            env.PORTFOLIO_REPOSITORY,
                            checkId,
                            env.PORTFOLIO_HEAD_SHA,
                            conclusion
                        )
                    } catch (Exception ignored) {
                        currentBuild.result = 'FAILURE'
                        echo 'Could not finalize the exact-SHA portfolio check; no token or raw API response was logged.'
                    }
                }
                if (env.PORTFOLIO_STATE != 'AUTHORIZED') {
                    currentBuild.result = 'FAILURE'
                    echo 'Portfolio authorization did not complete; no target checkout or repository command ran.'
                }
            }
        }
    }
}
