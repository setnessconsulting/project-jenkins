// Shared trusted helpers injected into the dispatcher and its scheduled reaper.
// The folder is dedicated to these centrally defined jobs only.
@com.cloudbees.groovy.cps.NonCPS
def portfolioFolderCredentialStore(def run) {
    def job = run?.getParent()
    def folder = job?.getParent()
    if (!(folder instanceof com.cloudbees.hudson.plugins.folder.Folder) ||
        folder.getFullName() != 'portfolio-dispatch' ||
        !(job.getFullName() in [
            'portfolio-dispatch/portfolio-pr-gate',
            'portfolio-dispatch/portfolio-checkout-credential-reaper'
        ])) {
        throw new IllegalStateException('Temporary checkout credentials are restricted to the dedicated portfolio-dispatch folder.')
    }

    def store = com.cloudbees.plugins.credentials.CredentialsProvider.lookupStores(folder).find { candidate ->
        candidate.getContext()?.is(folder)
    }
    if (store == null) {
        throw new IllegalStateException('The dedicated portfolio folder credential store is unavailable.')
    }
    return store
}

@com.cloudbees.groovy.cps.NonCPS
void portfolioCleanupStaleCheckoutCredentials(def run, long maxAgeMillis) {
    if (maxAgeMillis < 60 * 60 * 1000L) {
        throw new IllegalArgumentException('Temporary checkout credential cleanup must not run before the one-hour token expiry window.')
    }
    def store = portfolioFolderCredentialStore(run)
    def domain = com.cloudbees.plugins.credentials.domains.Domain.global()
    long cutoff = java.time.Instant.now().toEpochMilli() - maxAgeMillis
    def stale = store.getCredentials(domain).findAll { credential ->
        String credentialId = credential.id?.toString() ?: ''
        String description = credential.description?.toString() ?: ''
        if (!credentialId.startsWith('portfolio-checkout-') ||
            !description.startsWith('Portfolio checkout token temporary; created=')) return false
        def match = description =~ /created=([0-9]{13})/
        return match.find() && Long.parseLong(match.group(1)) < cutoff
    }
    stale.each { credential ->
        if (!store.removeCredentials(domain, credential)) {
            throw new IllegalStateException('The portfolio reaper could not remove an expired folder-scoped checkout credential.')
        }
    }
    if (!stale.isEmpty()) store.save()
}

@com.cloudbees.groovy.cps.NonCPS
void portfolioRemoveCheckoutCredential(def run, String credentialId) {
    if (!(credentialId ==~ /portfolio-checkout-[0-9a-f-]{36}/)) return
    def store = portfolioFolderCredentialStore(run)
    def domain = com.cloudbees.plugins.credentials.domains.Domain.global()
    def credential = store.getCredentials(domain).find { it.id == credentialId }
    if (credential == null) return
    String description = credential.description?.toString() ?: ''
    if (!description.startsWith('Portfolio checkout token temporary; created=')) {
        throw new IllegalStateException('The portfolio cleanup refused a credential outside its temporary-token contract.')
    }
    if (!store.removeCredentials(domain, credential)) {
        throw new IllegalStateException('The controller could not remove the temporary folder-scoped checkout credential.')
    }
    store.save()
}
