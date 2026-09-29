// Centrally trusted scheduled poller. It reads only the private profile catalog
// and same-repository PR metadata, then queues the existing trusted PR gate.
// It never checks out or executes target-repository code.
def portfolioPollAppCredentialId = /* JENKINS_PORTFOLIO_APP_CREDENTIAL_ID */
def portfolioPollCatalogRepository = /* JENKINS_PORTFOLIO_CATALOG_REPOSITORY */
def portfolioPollNodeBinary = /* JENKINS_PORTFOLIO_NODE_BINARY */
def portfolioPollAdapter = '/usr/share/jenkins/portfolio-profile-contract/src/plan-poll.mjs'

@com.cloudbees.groovy.cps.NonCPS
String portfolioPollScopedAppToken(def run, String credentialId, String repository, Map permissions) {
    def read = org.kohsuke.github.GHPermissionType.READ
    def permittedScopes = [
        [contents: read],
        [pull_requests: read],
        [checks: read]
    ]
    if (!(repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) || !(permissions in permittedScopes)) {
        throw new IllegalArgumentException('The portfolio poller requested an unsupported repository or App permission scope.')
    }
    def baseCredential = com.cloudbees.plugins.credentials.CredentialsProvider.findCredentialById(
        credentialId,
        org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials.class,
        run,
        java.util.Collections.emptyList()
    )
    if (baseCredential == null) {
        throw new IllegalStateException('The portfolio poller could not resolve the configured GitHub App credential.')
    }
    String[] parts = repository.split('/', 2)
    def scopedCredential = new org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials(
        com.cloudbees.plugins.credentials.CredentialsScope.GLOBAL,
        'portfolio-poll-temporary-token',
        'Ephemeral single-repository portfolio poll token',
        baseCredential.getAppID(),
        baseCredential.getPrivateKey()
    )
    if (baseCredential.getApiUri()) scopedCredential.setApiUri(baseCredential.getApiUri())
    scopedCredential.setRepositoryAccessStrategy(
        new org.jenkinsci.plugins.github_branch_source.app_credentials.AccessSpecifiedRepositories(parts[0], [parts[1]])
    )
    def usageContext = org.jenkinsci.plugins.github_branch_source.GitHubAppUsageContext.builder()
        .inferredOwner(parts[0])
        .inferredRepository(parts[1])
        .permissions(permissions)
        .build()
    String token = scopedCredential.contextualize(usageContext).getPassword()?.getPlainText()
    if (!token) throw new IllegalStateException('The portfolio poller could not mint a repository-scoped App token.')
    return token
}

@com.cloudbees.groovy.cps.NonCPS
Object portfolioPollApiJson(String token, String path) {
    if (!path?.startsWith('/repos/setnessconsulting/') || path.contains('..') || !token) {
        throw new IllegalArgumentException('The portfolio poll API request is outside its fixed GitHub boundary.')
    }
    int responseStatus = -1
    try {
        def request = java.net.http.HttpRequest.newBuilder(java.net.URI.create("https://api.github.com${path}"))
            .timeout(java.time.Duration.ofSeconds(20))
            .header('Accept', 'application/vnd.github+json')
            .header('Authorization', "Bearer ${token}")
            .header('X-GitHub-Api-Version', '2022-11-28')
            .GET()
            .build()
        def response = java.net.http.HttpClient.newBuilder()
            .connectTimeout(java.time.Duration.ofSeconds(10))
            .build()
            .send(request, java.net.http.HttpResponse.BodyHandlers.ofString(java.nio.charset.StandardCharsets.UTF_8))
        responseStatus = response.statusCode()
        if (responseStatus != 200 || response.body().getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 1024 * 1024) {
            throw new IllegalStateException('GitHub returned an unexpected status or oversized poll response.')
        }
        return new groovy.json.JsonSlurperClassic().parseText(response.body())
    } catch (InterruptedException interrupted) {
        Thread.currentThread().interrupt()
        throw new IllegalStateException('The portfolio poll API request was interrupted.')
    } catch (Exception ignored) {
        String statusHint = responseStatus >= 0 ? " (HTTP ${responseStatus})" : ''
        throw new IllegalStateException("The portfolio poll API request failed${statusHint}; no credential or raw response was logged.")
    }
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioPollReadCatalog(def run, String credentialId, String repository) {
    if (repository != 'setnessconsulting/project-jenkins-config') {
        throw new IllegalStateException('The portfolio poller requires the approved private configuration repository.')
    }
    String token = portfolioPollScopedAppToken(
        run, credentialId, repository, [contents: org.kohsuke.github.GHPermissionType.READ]
    )
    try {
        Map reference = (Map) portfolioPollApiJson(token, "/repos/${repository}/git/ref/heads/main")
        String catalogSha = reference?.object?.sha?.toString()?.toLowerCase()
        if (!(catalogSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
            throw new IllegalStateException('The portfolio poller could not resolve the private catalog main SHA.')
        }
        Map content = (Map) portfolioPollApiJson(
            token, "/repos/${repository}/contents/profiles/profiles.json?ref=${catalogSha}"
        )
        if (content?.type != 'file' || content?.encoding != 'base64' || !(content.content instanceof String)) {
            throw new IllegalStateException('The portfolio poller received an invalid private catalog file response.')
        }
        byte[] decoded = java.util.Base64.getDecoder().decode(content.content.replaceAll('\\s', ''))
        if (decoded.length == 0 || decoded.length > 1024 * 1024) {
            throw new IllegalStateException('The private portfolio catalog is empty or exceeds its input limit.')
        }
        try {
            return [sha: catalogSha, catalog: (Map) new groovy.json.JsonSlurperClassic().parseText(
                new String(decoded, java.nio.charset.StandardCharsets.UTF_8)
            )]
        } finally {
            java.util.Arrays.fill(decoded, (byte) 0)
        }
    } finally {
        token = null
    }
}

@com.cloudbees.groovy.cps.NonCPS
List portfolioPollOpenPullRequests(def run, String credentialId, String repository) {
    List result = []
    String token = portfolioPollScopedAppToken(
        run, credentialId, repository, [pull_requests: org.kohsuke.github.GHPermissionType.READ]
    )
    try {
        for (int page = 1; page <= 10; page++) {
            List items = (List) portfolioPollApiJson(
                token, "/repos/${repository}/pulls?state=open&per_page=100&page=${page}"
            )
            if (items == null || items.size() > 100) {
                throw new IllegalStateException('The portfolio poller received an invalid PR page.')
            }
            result.addAll(items)
            if (items.size() < 100) return result
        }
        throw new IllegalStateException('The portfolio poller reached its PR pagination limit; no partial dispatch was queued.')
    } finally {
        token = null
    }
}

@com.cloudbees.groovy.cps.NonCPS
String portfolioPollAppId(def run, String credentialId) {
    def appCredential = com.cloudbees.plugins.credentials.CredentialsProvider.findCredentialById(
        credentialId,
        org.jenkinsci.plugins.github_branch_source.GitHubAppCredentials.class,
        run,
        java.util.Collections.emptyList()
    )
    String appId = appCredential?.getAppID()?.toString()
    if (!(appId ==~ /[0-9]{1,20}/)) throw new IllegalStateException('The configured GitHub App identity is unavailable.')
    return appId
}

@com.cloudbees.groovy.cps.NonCPS
String portfolioPollCheckObservation(def run, String credentialId, String repository, String headSha, String expectedAppId) {
    if (!(repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
        !(headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/) || !(expectedAppId ==~ /[0-9]{1,20}/)) {
        throw new IllegalArgumentException('The poller check lookup received invalid trusted metadata.')
    }
    String token = portfolioPollScopedAppToken(
        run, credentialId, repository, [checks: org.kohsuke.github.GHPermissionType.READ]
    )
    try {
        Map response = (Map) portfolioPollApiJson(
            token, "/repos/${repository}/commits/${headSha}/check-runs?check_name=jenkins-pr-gate&app_id=${expectedAppId}&filter=all&per_page=100"
        )
        if (!(response.total_count instanceof Number) || !(response.check_runs instanceof List) ||
            response.check_runs.size() > 100) {
            throw new IllegalStateException('GitHub returned an invalid exact-SHA check-run response.')
        }
        List matching = response.check_runs.findAll { runResult ->
            runResult?.name == 'jenkins-pr-gate' && runResult?.head_sha?.toString()?.equalsIgnoreCase(headSha) &&
                runResult?.app?.id?.toString() == expectedAppId
        }
        if (matching.isEmpty()) return 'missing'
        Map latest = (Map) matching.max { item ->
            (item?.updated_at ?: item?.created_at ?: '').toString()
        }
        if (latest.status == 'in_progress' || latest.status == 'queued' || latest.status == 'requested') {
            return 'in_progress'
        }
        if (latest.status == 'completed') return 'completed'
        throw new IllegalStateException('The Jenkins App check-run has an unsupported terminal status.')
    } finally {
        token = null
    }
}

@com.cloudbees.groovy.cps.NonCPS
File portfolioPollStateFile() {
    String homeValue = System.getenv('JENKINS_HOME') ?: ''
    if (!homeValue.startsWith('/')) throw new IllegalStateException('The portfolio poller requires an absolute controller home.')
    File home = new File(homeValue).canonicalFile
    File directory = new File(home, 'portfolio-dispatch').canonicalFile
    if (!directory.path.startsWith(home.path + File.separator)) {
        throw new IllegalStateException('The portfolio poll state escaped controller home.')
    }
    return new File(directory, 'pr-poll-state.json')
}

@com.cloudbees.groovy.cps.NonCPS
List portfolioPollReadState() {
    File stateFile = portfolioPollStateFile()
    if (!stateFile.exists()) return []
    if (!stateFile.isFile() || stateFile.length() > 2 * 1024 * 1024) {
        throw new IllegalStateException('The portfolio poll state is not a bounded regular file.')
    }
    Object parsed = new groovy.json.JsonSlurperClassic().parseText(stateFile.getText('UTF-8'))
    if (!(parsed instanceof List)) throw new IllegalStateException('The portfolio poll state has an invalid format.')
    return (List) parsed
}

@com.cloudbees.groovy.cps.NonCPS
void portfolioPollWriteState(List state) {
    File stateFile = portfolioPollStateFile()
    File directory = stateFile.parentFile
    if (!directory.exists() && !directory.mkdirs()) {
        throw new IllegalStateException('The portfolio poll state directory could not be created.')
    }
    byte[] content = groovy.json.JsonOutput.toJson(state).getBytes(java.nio.charset.StandardCharsets.UTF_8)
    if (content.length > 2 * 1024 * 1024) throw new IllegalStateException('The portfolio poll state exceeded its size limit.')
    File temporary = File.createTempFile('pr-poll-state-', '.tmp', directory)
    try {
        java.nio.file.Files.write(temporary.toPath(), content)
        temporary.setReadable(false, false)
        temporary.setReadable(true, true)
        temporary.setWritable(false, false)
        temporary.setWritable(true, true)
        java.nio.file.Files.move(
            temporary.toPath(), stateFile.toPath(),
            java.nio.file.StandardCopyOption.ATOMIC_MOVE,
            java.nio.file.StandardCopyOption.REPLACE_EXISTING
        )
    } finally {
        java.util.Arrays.fill(content, (byte) 0)
        if (temporary.exists()) temporary.delete()
    }
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioPollDrain(java.io.InputStream stream, int maximumBytes) {
    java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream()
    byte[] buffer = new byte[8192]
    long totalBytes = 0
    boolean oversized = false
    int count
    while ((count = stream.read(buffer)) != -1) {
        long remaining = maximumBytes - totalBytes
        if (remaining > 0) output.write(buffer, 0, (int) Math.min(count, remaining))
        totalBytes += count
        if (totalBytes > maximumBytes) oversized = true
    }
    return [content: output.toByteArray(), oversized: oversized]
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioPollPlan(def run, String nodeBinary, String adapterPath, Map envelope) {
    byte[] input = groovy.json.JsonOutput.toJson(envelope).getBytes(java.nio.charset.StandardCharsets.UTF_8)
    if (input.length == 0 || input.length > 2 * 1024 * 1024) {
        throw new IllegalArgumentException('The trusted poll plan input is empty or too large.')
    }
    Process process = null
    java.util.concurrent.ExecutorService readers = java.util.concurrent.Executors.newFixedThreadPool(2)
    try {
        process = new ProcessBuilder(nodeBinary, adapterPath).start()
        def stdoutFuture = readers.submit({ ->
            portfolioPollDrain(process.getInputStream(), 2 * 1024 * 1024)
        } as java.util.concurrent.Callable)
        def stderrFuture = readers.submit({ ->
            portfolioPollDrain(process.getErrorStream(), 4096)
        } as java.util.concurrent.Callable)
        process.outputStream.withCloseable { stream -> stream.write(input) }
        if (!process.waitFor(30, java.util.concurrent.TimeUnit.SECONDS)) {
            process.destroyForcibly()
            throw new IllegalStateException('The trusted portfolio poll planner exceeded its controller time limit.')
        }
        Map stdout = (Map) stdoutFuture.get(2, java.util.concurrent.TimeUnit.SECONDS)
        Map stderr = (Map) stderrFuture.get(2, java.util.concurrent.TimeUnit.SECONDS)
        if (stdout.oversized || stderr.oversized) {
            throw new IllegalStateException('The trusted portfolio poll planner returned oversized output.')
        }
        String output = new String((byte[]) stdout.content, java.nio.charset.StandardCharsets.UTF_8)
        String errors = new String((byte[]) stderr.content, java.nio.charset.StandardCharsets.UTF_8)
        if (process.exitValue() != 0) {
            Map rejection = errors ? (Map) new groovy.json.JsonSlurperClassic().parseText(errors.trim()) : [:]
            String code = rejection?.code?.toString()
            if (!(code ==~ /[a-z0-9-]{1,64}/)) code = 'poll-plan-rejected'
            throw new IllegalStateException("The private portfolio catalog or poll input was rejected (${code}).")
        }
        Map plan = (Map) new groovy.json.JsonSlurperClassic().parseText(output.trim())
        if (!(plan.status in ['ready', 'inactive']) || !(plan.dispatches instanceof List) || !(plan.state instanceof List)) {
            throw new IllegalStateException('The trusted portfolio poll planner returned an invalid plan.')
        }
        return plan
    } catch (InterruptedException interrupted) {
        Thread.currentThread().interrupt()
        throw new IllegalStateException('The trusted portfolio poll planner was interrupted.')
    } catch (Exception ignored) {
        if (ignored instanceof IllegalStateException && ignored.message?.startsWith('The private portfolio catalog')) {
            throw ignored
        }
        throw new IllegalStateException('The controller could not run the trusted portfolio poll planner.')
    } finally {
        if (process != null && process.isAlive()) process.destroyForcibly()
        readers.shutdownNow()
        java.util.Arrays.fill(input, (byte) 0)
    }
}

@com.cloudbees.groovy.cps.NonCPS
boolean portfolioPollGateBusy() {
    def jenkins = jenkins.model.Jenkins.get()
    def gate = jenkins.getItemByFullName('portfolio-dispatch/portfolio-pr-gate')
    if (gate == null) throw new IllegalStateException('The trusted portfolio PR gate job is unavailable.')
    boolean running = gate.getBuilds().any { build -> build.isBuilding() }
    boolean queued = jenkins.getQueue().getItems().any { item -> item.task?.getFullName() == gate.getFullName() }
    return running || queued
}

pipeline {
    agent none

    options {
        timeout(time: 10, unit: 'MINUTES')
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    stages {
        stage('Discover and queue one exact-SHA PR') {
            steps {
                script {
                    if (portfolioPollGateBusy()) {
                        echo 'A portfolio PR gate is already running or queued; this poll will not add more queue pressure.'
                        return
                    }

                    Map catalogSnapshot = portfolioPollReadCatalog(
                        currentBuild.rawBuild,
                        portfolioPollAppCredentialId,
                        portfolioPollCatalogRepository
                    )
                    Map targetPlan = portfolioPollPlan(currentBuild.rawBuild, portfolioPollNodeBinary, portfolioPollAdapter, [
                        mode: 'targets',
                        catalog: catalogSnapshot.catalog
                    ])
                    if (targetPlan.status == 'inactive') {
                        echo 'The private portfolio control plane is not active; no repository was queried or dispatched.'
                        return
                    }
                    if (!(targetPlan.repositories instanceof List) || targetPlan.repositories.size() > 40 ||
                        targetPlan.repositories.any { !(it ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) }) {
                        error('The trusted poll planner returned an invalid or oversized repository list.')
                    }
                    if (targetPlan.repositories.isEmpty()) {
                        echo 'No shadow or qualified portfolio profile uses an enabled routine implementation.'
                        return
                    }

                    List pullRequestsByRepository = targetPlan.repositories.collect { repository ->
                        [
                            repository: repository,
                            pullRequests: portfolioPollOpenPullRequests(
                                currentBuild.rawBuild,
                                portfolioPollAppCredentialId,
                                repository.toString()
                            )
                        ]
                    }
                    List previousState = portfolioPollReadState()
                    Map openPullRequestByKey = [:]
                    pullRequestsByRepository.each { record ->
                        record.pullRequests.each { pullRequest ->
                            openPullRequestByKey["${record.repository.toString().toLowerCase()}#${pullRequest.number}"] = pullRequest
                        }
                    }
                    List observations = []
                    String expectedAppId = portfolioPollAppId(currentBuild.rawBuild, portfolioPollAppCredentialId)
                    previousState.each { entry ->
                        if (!(entry instanceof Map) || !(entry.status in ['pending', 'stalled'])) return
                        String priorRepository = entry.repository?.toString() ?: ''
                        String priorSha = entry.headSha?.toString() ?: ''
                        if (!(priorRepository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
                            !(entry.pullRequestNumber instanceof Number) || !(priorSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
                            error('The controller poll state contains invalid pending metadata; no downstream job was queued.')
                        }
                        Map openPullRequest = (Map) openPullRequestByKey["${priorRepository.toLowerCase()}#${entry.pullRequestNumber}"]
                        String currentSha = openPullRequest?.head?.sha?.toString()
                        if (currentSha?.equalsIgnoreCase(priorSha)) {
                            observations.add([
                                repository: priorRepository,
                                pullRequestNumber: entry.pullRequestNumber as Integer,
                                headSha: priorSha.toLowerCase(),
                                status: portfolioPollCheckObservation(
                                    currentBuild.rawBuild, portfolioPollAppCredentialId, priorRepository, priorSha, expectedAppId
                                )
                            ])
                        }
                    }
                    Map plan = portfolioPollPlan(currentBuild.rawBuild, portfolioPollNodeBinary, portfolioPollAdapter, [
                        mode: 'plan',
                        catalog: catalogSnapshot.catalog,
                        pullRequestsByRepository: pullRequestsByRepository,
                        previousState: previousState,
                        checkObservations: observations,
                        nowEpochMs: System.currentTimeMillis()
                    ])
                    if (plan.status == 'inactive') {
                        echo 'The private portfolio control plane became inactive; nothing was queued.'
                        return
                    }
                    List state = plan.state
                    List dispatches = plan.dispatches
                    if (dispatches.isEmpty()) {
                        portfolioPollWriteState(state)
                        int stalledCount = state.count { entry -> entry.status == 'stalled' }
                        echo "No exact PR head SHA requires a new Jenkins shadow run; ${stalledCount} missing-check case(s) reached the bounded retry limit and need operator attention."
                        return
                    }

                    Map dispatch = (Map) dispatches[0]
                    if (!(dispatch.repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
                        !(dispatch.pullRequestNumber.toString() ==~ /[1-9][0-9]{0,8}/) ||
                        !(dispatch.headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
                        error('The trusted poll planner returned invalid dispatch metadata; no downstream build was queued.')
                    }
                    // Persist the attempt intent before queueing: if this poller is
                    // canceled after scheduling, the next run can reconcile it.
                    portfolioPollWriteState(state)
                    build job: 'portfolio-dispatch/portfolio-pr-gate',
                        parameters: [
                            string(name: 'TARGET_REPOSITORY', value: dispatch.repository.toString()),
                            string(name: 'PULL_REQUEST_NUMBER', value: dispatch.pullRequestNumber.toString()),
                            string(name: 'EXPECTED_HEAD_SHA', value: dispatch.headSha.toString())
                        ],
                        wait: false,
                        propagate: false
                    echo "Queued centrally trusted Jenkins shadow verification for ${dispatch.repository} PR #${dispatch.pullRequestNumber} at ${dispatch.headSha} (attempt ${dispatch.attempt}). No target Pipeline was loaded."
                }
            }
        }
    }
}
