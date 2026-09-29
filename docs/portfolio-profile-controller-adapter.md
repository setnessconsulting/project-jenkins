# Portfolio profile controller adapter

`integration/portfolio-profile-contract/src/resolve-pr.mjs` is a bounded stdin
adapter for the centrally trusted profile resolver. It accepts one closed JSON
envelope containing the private profile catalog, trusted GitHub PR metadata,
and a request with repository identity, PR number, and exact head SHA. It caps
input at 1 MiB, rejects command-line arguments and caller-supplied author
policy, fixes the initial allowlist to `setnessconsulting`, and returns only a
centrally defined execution plan or a stable rejection code.

The manual-only `portfolio-dispatch/portfolio-pr-gate` job now assembles the catalog and PR object
on the controller. It pins the private catalog file to a resolved `main` commit,
uses one-repository App tokens for catalog read, PR read, checkout, and Checks
publication, and refreshes the PR again after an agent becomes available.
Checkout uses a temporary contents-read credential for only that repository;
it is stored in the dedicated folder credentials store (not the controller-
wide System store). The controller removes it immediately after checkout and
again in `finally`, while a separate 15-minute maintenance job reaps expired
entries independently of later PR dispatches.
The publisher token and App private key remain controller-side. The job never
accepts a target Jenkinsfile or a profile ID from its caller. The Dockerfile
packages the adapter only into the controller image; the agent images do not include it.

This is a manual shadow dispatcher, not routine portfolio automation. It has no
polling schedule, and a centrally coded implementation allowlist must also
match a private catalog profile with `status: shadow` before any checkout.
The dispatcher is always declared but disabled unless the private catalog
repository is provided through ignored local runtime configuration. The old
root-level job name is explicitly replaced by a disabled deprecation stub, so
clearing configuration cannot leave an older dispatcher runnable.
Profiles remain planned until their matching runtime is loaded and ready; no
repository is enabled merely by adding the dispatcher. Existing pilot jobs are
not routed through it, avoiding duplicate check publishers. Actions remains authoritative.
Jenkins must still prove the live controller configuration, agent availability,
exact-SHA results, cleanup, recovery, and fallback before any cutover.
