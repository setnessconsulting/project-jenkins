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
After the live same-repository PR identity is confirmed and a full requested
SHA is supplied, the controller opens the exact-SHA check before reading the
private catalog or resolving a profile. Pipeline finalization publishes a
failure if those authorization steps reject the request, so a safe-target
resolution failure does not leave the check absent or pending. Requests without
a verifiable same-repository PR identity are rejected before a check is
targeted.
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
head SHA, check name, and GitHub App ID. For an in-progress check, it resolves
the check's Jenkins external ID to the centrally trusted gate job and verifies
the per-dispatch UUID stored in controller state. This avoids selecting a
"latest" check using timestamps that the Check Runs API does not return. It
then verifies the referenced build's repository, PR, SHA, and dispatch UUID. A
live match is left alone, including a legitimately long-running build. A
matching check whose build is no longer queued or running is treated as
orphaned; after the 15-minute grace period the controller re-reads it, verifies
identity again, and uses a controller-only `checks:write` token to finish it as
a visible failure. That distinct recovery-failure marker remains retryable if
the poller is interrupted before scheduling the replacement. Build identity
mismatches or checks from another Jenkins job are untracked and are never
overwritten or retried; they surface as operator attention after the grace
period. The poller accepts same-repository
non-draft PRs by `setnessconsulting` only, and queues one exact-head SHA at a
time. Only the selected PR advances retry state; eligible PRs waiting behind it
are not counted as attempted. The poller never checks out repository code.
Checks whose external ID does not identify this exact trusted gate job are
treated as untracked: the poller does not overwrite or duplicate another job's
result, and raises operator attention after the grace period.

The bounded state file is stored under Jenkins home and records the exact SHA,
attempt count, dispatch time, and pending/completed/stalled state. A missing
check is given a 15-minute visibility/startup grace period and retried at most
three times; a matching completed check is terminal. A live in-progress check
is never duplicated, while an abandoned in-progress check is completed with a
failure conclusion so it cannot remain pending indefinitely. After the retry
limit, the poller reports an operator attention item instead of silently
suppressing that SHA forever or retrying without limit. The poller persists the
selected dispatch intent before queueing so a poller cancellation after
downstream scheduling can be reconciled on its next run; unselected candidates
do not consume attempts. Every automated queue request gets a controller-
generated UUID, propagated to the trusted gate and embedded in the check's
external ID. Manual gate runs leave that field blank and cannot be mistaken for
a poller-owned check.
The dispatcher is always declared but disabled unless the private catalog
repository is provided through ignored local runtime configuration. The old
root-level job name is explicitly replaced by a disabled deprecation stub, so
clearing configuration cannot leave an older dispatcher runnable.
The central routine-poller allowlist is an explicit set of implementation and
repository pairs. It includes the centrally implemented lanes documented in
`portfolio-profile-contract.md`, including the credential-free Investment
Council Node 22 lane, the Jira Admin Python 3.12 lane, and the Supabase API
Node 22 lane, the Rive API Node 22 lane, the Game Signal Garden Python
3.12 lane, and the Jira Platform Node 22.14 API lane, and now contains
twenty-two exact pairs in total. The
Game Maker pair uses the existing `project-game-maker-python312` profile and
fixed implementation to run both Python 3.11.17 and 3.12.14 command sequences
on a one-build, unprivileged dual-runtime agent. The image source hashes and
versions are pinned, and the commands stay centrally owned. Its Actions
workflow still selects a floating Python 3.11 patch, so runtime parity is not
claimed; the Jenkins image must be built and deployed before the lane can run.
The Unity API pair is pinned to the `project-unity-api` repository and
the fixed Node 22.14 `npm ci` / `npm run maintenance` command plan. The Jira API
pair uses the centrally pinned Node 22.14 clean-checkout
implementation. The agent checks its pinned runtime after exact-SHA checkout
and before running repository commands. Adding a pair does not change its
catalog status or make it Jenkins-authoritative; planned profiles remain
excluded. Existing pilot jobs are
not routed through it, avoiding duplicate check publishers. Actions remains authoritative.
Jenkins must still prove the live controller configuration, agent availability,
exact-SHA results, cleanup, recovery, and fallback before any cutover.

Qualification records the exact-SHA cases needed by a profile-specific evidence
matrix rather than requiring a fixed count. Every case must cover a distinct
required behavior, and all recorded cases must pass. Isolation, cleanup and
recovery, owner-controlled fallback, and owner-approved protection readback
remain separate requirements.
