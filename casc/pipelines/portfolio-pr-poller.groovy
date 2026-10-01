// Centrally trusted scheduled poller. It reads only the private profile catalog
// and same-repository PR metadata, then queues the existing trusted PR gate.
// It never checks out or executes target-repository code.
def portfolioPollAppCredentialId = /* JENKINS_PORTFOLIO_APP_CREDENTIAL_ID */
def portfolioPollCatalogRepository = /* JENKINS_PORTFOLIO_CATALOG_REPOSITORY */
def portfolioPollNodeBinary = /* JENKINS_PORTFOLIO_NODE_BINARY */
def portfolioPollAdapter = '/usr/share/jenkins/portfolio-profile-contract/src/plan-poll.mjs'

// Controller capabilities the poller -> gate dispatch path depends on: the step
// that queues the gate, the steps the gate needs to publish its check run, and
// the resources and agent cloud the whole path runs on. Asserting them up front
// turns a broken controller image into one loud, actionable failure at the
// start of the run instead of an opaque error at the queue step, after the
// poller has already retried on its five-minute schedule. The deploy-time
// check in scripts/vm/start-jenkins.sh asserts the same set, and
// scripts/verify-pipeline-contract.ps1 keeps this list in step with plugins.txt.
def portfolioPollRequiredPlugins = ['pipeline-build-step', 'github-checks', 'workflow-cps', 'workflow-basic-steps', 'workflow-durable-task-step', 'workflow-job', 'workflow-scm-step', 'github-branch-source', 'docker-plugin']
def portfolioPollRequiredStepSymbols = ['build', 'withChecks', 'publishChecks', 'checkout', 'node', 'sh', 'writeFile', 'readFile', 'timeout', 'echo', 'error']

// Fail-closed capability preflight. Returns a loud message naming every missing
// capability, or null when the dispatch path can run. It reads only Jenkins
// core state and never resolves a credential. The markers below delimit the
// exact block that the read-only console probe in
// _evidence/jenkins-pipeline-build-step-20261001/ evaluates against a live
// controller, so keep them in place.
// BEGIN JENKINS_PORTFOLIO_CAPABILITY_PREFLIGHT
@com.cloudbees.groovy.cps.NonCPS
String portfolioPollControllerCapabilityGap(List requiredPlugins, List requiredStepSymbols, String nodeBinary, String adapterPath) {
    def jenkins = jenkins.model.Jenkins.get()
    def pluginManager = jenkins.getPluginManager()
    List gaps = []
    requiredPlugins.each { name ->
        def plugin = pluginManager.getPlugin(name.toString())
        if (plugin == null || !plugin.isActive()) gaps.add("plugin ${name}")
    }
    try {
        Set availableSymbols = jenkins.getDescriptorList(org.jenkinsci.plugins.workflow.steps.Step.class)
            .collect { descriptor -> descriptor.functionName } as Set
        requiredStepSymbols.each { symbol ->
            if (!availableSymbols.contains(symbol.toString())) gaps.add("step ${symbol}")
        }
    } catch (Throwable failure) {
        gaps.add("step enumeration (${failure.getClass().getSimpleName()})")
    }
    if (!(nodeBinary instanceof String) || !new File(nodeBinary).canExecute()) gaps.add("controller Node binary ${nodeBinary}")
    if (!(adapterPath instanceof String) || !new File(adapterPath).isFile()) gaps.add("trusted poll adapter ${adapterPath}")
    // This core exposes the configured clouds as the `clouds` property; it has no
    // getClouds() accessor, and getCloud() returns a UI model rather than a
    // collection, so the property is the only way to see whether any cloud can
    // provision the gate's one-use agent.
    try {
        if (!jenkins.clouds) gaps.add('agent cloud')
    } catch (Throwable failure) {
        gaps.add("agent cloud enumeration (${failure.getClass().getSimpleName()})")
    }
    if (gaps.isEmpty()) return null
    return 'Portfolio dispatch capability preflight FAILED, so the poller to gate dispatch path cannot run: ' + gaps.join('; ') +
        '. No PR was dispatched and no gate build was queued. Fix the controller image (plugins.txt) or its configuration, then re-run scripts/vm/start-jenkins.sh verify before expecting portfolio shadow evidence.'
}
// END JENKINS_PORTFOLIO_CAPABILITY_PREFLIGHT

@com.cloudbees.groovy.cps.NonCPS
String portfolioPollScopedAppToken(def run, String credentialId, String repository, Map permissions) {
    def read = org.kohsuke.github.GHPermissionType.READ
    def write = org.kohsuke.github.GHPermissionType.WRITE
    def permittedScopes = [
        [contents: read],
        [pull_requests: read],
        [checks: read],
        [checks: write]
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
Object portfolioPollApiPatchJson(String token, String path, Map payload) {
    if (!path?.startsWith('/repos/setnessconsulting/') || path.contains('..') || !token || !(payload instanceof Map)) {
        throw new IllegalArgumentException('The portfolio poll API update is outside its fixed GitHub boundary.')
    }
    int responseStatus = -1
    try {
        String body = groovy.json.JsonOutput.toJson(payload)
        def request = java.net.http.HttpRequest.newBuilder(java.net.URI.create("https://api.github.com${path}"))
            .timeout(java.time.Duration.ofSeconds(20))
            .header('Accept', 'application/vnd.github+json')
            .header('Authorization', "Bearer ${token}")
            .header('X-GitHub-Api-Version', '2022-11-28')
            .header('Content-Type', 'application/json')
            .method('PATCH', java.net.http.HttpRequest.BodyPublishers.ofString(body))
            .build()
        def response = java.net.http.HttpClient.newBuilder()
            .connectTimeout(java.time.Duration.ofSeconds(10))
            .build()
            .send(request, java.net.http.HttpResponse.BodyHandlers.ofString())
        responseStatus = response.statusCode()
        if (responseStatus != 200 || response.body().getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 1024 * 1024) {
            throw new IllegalStateException('GitHub returned an unexpected status or oversized check update response.')
        }
        return new groovy.json.JsonSlurperClassic().parseText(response.body())
    } catch (InterruptedException interrupted) {
        Thread.currentThread().interrupt()
        throw new IllegalStateException('The portfolio poll check update was interrupted.')
    } catch (Exception ignored) {
        String statusHint = responseStatus >= 0 ? " (HTTP ${responseStatus})" : ''
        throw new IllegalStateException("The portfolio poll check update failed${statusHint}; no credential or raw response was logged.")
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
boolean portfolioPollHasExpectedBuildIdentity(Map checkRun, String dispatchId) {
    String externalId = checkRun?.external_id?.toString() ?: ''
    if (!(dispatchId ==~ /(?i)[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/)) return false
    return externalId ==~ /jenkins:portfolio-dispatch\/portfolio-pr-gate#[1-9][0-9]{0,8};portfolio-dispatch:${dispatchId.toLowerCase()}/
}

@com.cloudbees.groovy.cps.NonCPS
String portfolioPollBuildCorrelation(Map checkRun, String repository, int pullRequestNumber, String headSha, String dispatchId) {
    String externalId = checkRun?.external_id?.toString() ?: ''
    if (!portfolioPollHasExpectedBuildIdentity(checkRun, dispatchId)) return 'untracked'
    int dispatchMarker = externalId.lastIndexOf(';portfolio-dispatch:')
    String buildId = externalId.substring('jenkins:'.length(), dispatchMarker)
    int separator = buildId.lastIndexOf('#')
    if (separator < 1 || separator == buildId.length() - 1 ||
        buildId.substring(0, separator) != 'portfolio-dispatch/portfolio-pr-gate' ||
        !(buildId.substring(separator + 1) ==~ /[1-9][0-9]{0,8}/)) return 'untracked'
    int buildNumber = Integer.parseInt(buildId.substring(separator + 1))
    def jenkins = jenkins.model.Jenkins.get()
    def job = jenkins.getItemByFullName('portfolio-dispatch/portfolio-pr-gate')
    if (!(job instanceof hudson.model.Job)) return 'orphaned'
    def build = job.getBuildByNumber(buildNumber)
    if (build == null) return 'orphaned'
    if (build.getExternalizableId() != buildId) return 'untracked'
    def parameters = build.getAction(hudson.model.ParametersAction.class)
    String buildRepository = parameters?.getParameter('TARGET_REPOSITORY')?.value?.toString()
    String buildPullRequest = parameters?.getParameter('PULL_REQUEST_NUMBER')?.value?.toString()
    String buildSha = parameters?.getParameter('EXPECTED_HEAD_SHA')?.value?.toString()
    String buildDispatchId = parameters?.getParameter('PORTFOLIO_DISPATCH_ID')?.value?.toString()
    if (!buildRepository?.equalsIgnoreCase(repository) || buildPullRequest != pullRequestNumber.toString() ||
        !buildSha?.equalsIgnoreCase(headSha) || !buildDispatchId?.equalsIgnoreCase(dispatchId)) return 'untracked'
    return build.isBuilding() ? 'in_progress' : 'orphaned'
}

@com.cloudbees.groovy.cps.NonCPS
Map portfolioPollCheckObservation(def run, String credentialId, String repository, int pullRequestNumber,
    String headSha, String expectedAppId, String dispatchId) {
    if (!(repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
        pullRequestNumber < 1 || !(headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/) ||
        !(expectedAppId ==~ /[0-9]{1,20}/)) {
        throw new IllegalArgumentException('The poller check lookup received invalid trusted metadata.')
    }
    if (!(dispatchId ==~ /(?i)[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/)) {
        return [status: 'untracked']
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
                runResult?.app?.id?.toString() == expectedAppId &&
                portfolioPollHasExpectedBuildIdentity(runResult as Map, dispatchId)
        }
        if (matching.isEmpty()) return [status: 'missing']
        if (matching.size() != 1) throw new IllegalStateException('A poll dispatch resolved to multiple GitHub check runs.')
        Map exactCheck = (Map) matching[0]
        if (!(exactCheck.id instanceof Number) || !(exactCheck.external_id instanceof String) || exactCheck.external_id.length() > 512) {
            throw new IllegalStateException('The exact poller check lacks a valid bounded identity.')
        }
        if (exactCheck.status == 'in_progress' || exactCheck.status == 'queued' || exactCheck.status == 'requested') {
            return [
                status: portfolioPollBuildCorrelation(exactCheck, repository, pullRequestNumber, headSha, dispatchId),
                checkRun: exactCheck
            ]
        }
        if (exactCheck.status == 'completed') {
            boolean recoveryFailure = exactCheck.conclusion == 'failure' &&
                exactCheck.output?.title == 'Jenkins run disappeared; recovery will retry'
            return [status: recoveryFailure ? 'orphaned' : 'completed', checkRun: exactCheck]
        }
        throw new IllegalStateException('The Jenkins App check-run has an unsupported terminal status.')
    } finally {
        token = null
    }
}

@com.cloudbees.groovy.cps.NonCPS
String portfolioPollRecoverOrphanedCheck(def run, String credentialId, String repository, int pullRequestNumber,
    String headSha, String expectedAppId, String dispatchId, Map observedCheck) {
    if (!(observedCheck?.id instanceof Number) || observedCheck.id.longValue() < 1 ||
        observedCheck?.name != 'jenkins-pr-gate' || !observedCheck?.head_sha?.toString()?.equalsIgnoreCase(headSha) ||
        observedCheck?.app?.id?.toString() != expectedAppId || observedCheck?.status != 'in_progress' ||
        !portfolioPollHasExpectedBuildIdentity(observedCheck, dispatchId)) {
        throw new IllegalArgumentException('The poller cannot recover an unverified or non-pending check run.')
    }
    String token = portfolioPollScopedAppToken(
        run, credentialId, repository, [checks: org.kohsuke.github.GHPermissionType.WRITE]
    )
    try {
        String path = "/repos/${repository}/check-runs/${observedCheck.id.longValue()}"
        Map current = (Map) portfolioPollApiJson(token, path)
        if (current?.id?.toString() != observedCheck.id.toString() || current?.name != 'jenkins-pr-gate' ||
            !current?.head_sha?.toString()?.equalsIgnoreCase(headSha) || current?.app?.id?.toString() != expectedAppId ||
            !portfolioPollHasExpectedBuildIdentity(current, dispatchId)) {
            throw new IllegalStateException('The orphaned check changed identity during recovery; no update was applied.')
        }
        if (current.status == 'completed') {
            return current.conclusion == 'failure' && current.output?.title == 'Jenkins run disappeared; recovery will retry'
                ? 'orphaned' : 'completed'
        }
        if (current.status != 'in_progress' || current.external_id != observedCheck.external_id) {
            throw new IllegalStateException('The orphaned check is no longer the expected in-progress Jenkins result.')
        }
        String correlation = portfolioPollBuildCorrelation(current, repository, pullRequestNumber, headSha, dispatchId)
        if (correlation != 'orphaned') return correlation
        Map updated = (Map) portfolioPollApiPatchJson(token, path, [
            status: 'completed',
            conclusion: 'failure',
            completed_at: java.time.Instant.now().toString(),
            output: [
                title: 'Jenkins run disappeared; recovery will retry',
                summary: 'The Jenkins build linked to this check is no longer queued or running. This infrastructure recovery is a failed verification result, not a pass; the trusted poller may retry this exact PR head within its bounded retry policy.'
            ]
        ])
        if (updated?.id?.toString() != observedCheck.id.toString() || updated?.name != 'jenkins-pr-gate' ||
            !updated?.head_sha?.toString()?.equalsIgnoreCase(headSha) || updated?.app?.id?.toString() != expectedAppId ||
            updated?.external_id != observedCheck.external_id || updated?.status != 'completed' ||
            updated?.conclusion != 'failure' || updated?.output?.title != 'Jenkins run disappeared; recovery will retry') {
            throw new IllegalStateException('GitHub did not confirm the failed terminal state for the orphaned check.')
        }
        return 'orphaned'
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
        stage('Assert controller capabilities') {
            steps {
                script {
                    String capabilityGap = portfolioPollControllerCapabilityGap(
                        portfolioPollRequiredPlugins,
                        portfolioPollRequiredStepSymbols,
                        portfolioPollNodeBinary,
                        portfolioPollAdapter
                    )
                    if (capabilityGap != null) {
                        error(capabilityGap)
                    }
                    echo 'Controller capability preflight passed: the gate queue step, the check-publication steps, the trusted poll adapter, and the agent cloud are all present.'
                }
            }
        }

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
                    long observationTime = System.currentTimeMillis()
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
                            Map checkObservation = portfolioPollCheckObservation(
                                currentBuild.rawBuild,
                                portfolioPollAppCredentialId,
                                priorRepository,
                                entry.pullRequestNumber as Integer,
                                priorSha,
                                expectedAppId,
                                entry.dispatchId?.toString() ?: ''
                            )
                            String observedStatus = checkObservation.status?.toString()
                            long dispatchedAt = (entry.dispatchedAtEpochMs as Number).longValue()
                            if (observedStatus == 'orphaned' && observationTime >= dispatchedAt &&
                                observationTime - dispatchedAt >= 15 * 60 * 1000L &&
                                checkObservation.checkRun?.status == 'in_progress') {
                                observedStatus = portfolioPollRecoverOrphanedCheck(
                                    currentBuild.rawBuild,
                                    portfolioPollAppCredentialId,
                                    priorRepository,
                                    entry.pullRequestNumber as Integer,
                                    priorSha,
                                    expectedAppId,
                                    entry.dispatchId?.toString() ?: '',
                                    (Map) checkObservation.checkRun
                                )
                            }
                            observations.add([
                                repository: priorRepository,
                                pullRequestNumber: entry.pullRequestNumber as Integer,
                                headSha: priorSha.toLowerCase(),
                                status: observedStatus
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

                    if (dispatches.size() != 1) {
                        error('The trusted poll planner must select exactly one dispatch; no downstream build was queued.')
                    }
                    Map dispatch = (Map) dispatches[0]
                    if (!(dispatch.repository ==~ /setnessconsulting\/[A-Za-z0-9._-]{1,100}/) ||
                        !(dispatch.pullRequestNumber.toString() ==~ /[1-9][0-9]{0,8}/) ||
                        !(dispatch.headSha ==~ /(?i)(?:[0-9a-f]{40}|[0-9a-f]{64})/)) {
                        error('The trusted poll planner returned invalid dispatch metadata; no downstream build was queued.')
                    }
                    String dispatchId = java.util.UUID.randomUUID().toString()
                    Map selectedState = (Map) state.find { entry ->
                        entry.repository?.toString()?.equalsIgnoreCase(dispatch.repository.toString()) &&
                            entry.pullRequestNumber?.toString() == dispatch.pullRequestNumber.toString() &&
                            entry.headSha?.toString()?.equalsIgnoreCase(dispatch.headSha.toString()) &&
                            entry.attempt?.toString() == dispatch.attempt.toString() && entry.status == 'pending'
                    }
                    if (selectedState == null) error('The planner did not return state for its selected dispatch; nothing was queued.')
                    selectedState.dispatchId = dispatchId
                    dispatch.dispatchId = dispatchId
                    // The planner returns at most one dispatch and advances only
                    // that selected PR's state. Persist its attempt intent before
                    // queueing so a canceled poller can reconcile the exact head;
                    // other eligible PRs are not counted as attempted.
                    portfolioPollWriteState(state)
                    build job: 'portfolio-dispatch/portfolio-pr-gate',
                        parameters: [
                            string(name: 'TARGET_REPOSITORY', value: dispatch.repository.toString()),
                            string(name: 'PULL_REQUEST_NUMBER', value: dispatch.pullRequestNumber.toString()),
                            string(name: 'EXPECTED_HEAD_SHA', value: dispatch.headSha.toString()),
                            string(name: 'PORTFOLIO_DISPATCH_ID', value: dispatchId)
                        ],
                        wait: false,
                        propagate: false
                    echo "Queued centrally trusted Jenkins shadow verification for ${dispatch.repository} PR #${dispatch.pullRequestNumber} at ${dispatch.headSha} (attempt ${dispatch.attempt}). No target Pipeline was loaded."
                }
            }
        }
    }
}
