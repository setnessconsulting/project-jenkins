# Portfolio profile controller adapter

`integration/portfolio-profile-contract/src/resolve-pr.mjs` is a bounded stdin
adapter for the centrally trusted profile resolver. It accepts one closed JSON
envelope containing the private profile catalog, trusted GitHub PR metadata,
and a request with repository identity, PR number, and exact head SHA. It caps
input at 1 MiB, rejects command-line arguments and caller-supplied author
policy, fixes the initial allowlist to `setnessconsulting`, and returns only a
centrally defined execution plan or a stable rejection code.

The manual `portfolio-dispatch/portfolio-pr-gate` job now assembles the catalog and PR object
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

The manual shadow dispatcher remains available for controlled exact-SHA runs.
A separate `portfolio-dispatch/portfolio-pr-poller` job is scheduled every
five minutes, but is disabled unless both the private catalog location and
`JENKINS_PORTFOLIO_PR_POLL_ENABLED=true` are present. The default is `false`.
The private catalog must additionally set `controlPlane.status: active`; only
centrally allowlisted implementations and profiles marked `shadow` or
`qualified` are considered, and the downstream gate enforces the same status
set. The poller reads open PR metadata using short-lived single-repository
`contents:read` and `pull_requests:read` App tokens. For a previously queued
PR it also reads only the `checks:read` permission, then reconciles the exact
head SHA, check name, and GitHub App ID before deciding whether a run is still
in progress or terminal. It accepts same-repository non-draft PRs by
`setnessconsulting` only, and queues one exact-head SHA at a time. It never
checks out repository code.

The bounded state file is stored under Jenkins home and records the exact SHA,
attempt count, dispatch time, and pending/completed/stalled state. A missing
check is given a 15-minute visibility/startup grace period and retried at most
three times; a matching completed check is terminal, while an in-progress check
is never duplicated. After the retry limit, the poller reports an operator
attention item instead of silently suppressing that SHA forever or retrying
without limit. The poller persists dispatch intent before queueing so a
poller cancellation after downstream scheduling can be reconciled on its next
run.
The dispatcher is always declared but disabled unless the private catalog
repository is provided through ignored local runtime configuration. The old
root-level job name is explicitly replaced by a disabled deprecation stub, so
clearing configuration cannot leave an older dispatcher runnable.
Profiles remain planned until their matching runtime is loaded and ready; no
repository is enabled merely by adding the dispatcher. Existing pilot jobs are
not routed through it, avoiding duplicate check publishers. Actions remains authoritative.
Jenkins must still prove the live controller configuration, agent availability,
exact-SHA results, cleanup, recovery, and fallback before any cutover.
