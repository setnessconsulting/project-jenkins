# Opt-in secondary repository profile

This profile extends the centrally trusted Jenkins configuration to one additional repository without changing the first repository's job, credentials, Actions triggers, branch protections, or release behavior. It is disabled by default and remains shadow-only until separately qualified.

## Enablement prerequisites

Do not set `JENKINS_SECONDARY_REPO_ENABLED=true` until all of these are ready:

- The existing GitHub App is installed for the exact additional repository with only the required read and Checks permissions. The App private key remains on the controller.
- A separate repository-scoped, read-only checkout credential exists for that repository. Do not reuse the first repository's deploy key.
- `JENKINS_SECONDARY_TRUSTED_PR_AUTHORS` contains the explicitly approved same-repository PR author logins. Fork PRs are excluded. Empty, duplicate, or invalid author lists fail configuration.
- The target's default branch is `main`, the owner understands the polling-created shadow checks, and the GitHub Actions workflows remain unchanged.
- A production-smoke URL is added only after the owner reviews the exact HTTPS endpoint. Until then, Jenkins publishes a neutral “not configured” result and makes no live request.

Use the ignored local `.env` file for repository identity, credential IDs, author allowlist, and the reviewed smoke URL. The public `.env.example` deliberately contains no target repository identity or endpoint. Never put key material or passwords in `.env`.

## Verification behavior

- The multibranch job discovers `main` and same-repository PR heads using the existing controller-side GitHub App. It runs the checked-in trusted pipeline; it does not load a PR-supplied Jenkinsfile.
- Before allocating an agent or checking out code, the controller verifies the Branch Source PR head SHA and confirms the source owner/repository and author allowlist. A denied PR fails the gate without checkout or repository commands.
- For PRs, Jenkins tests the GitHub Branch Source synthetic merge revision, verifies its parents match the trusted PR base and head SHAs, and publishes the required check against the PR head SHA. Main-branch checks use the checked-out main commit SHA.
- `jenkins-pr-gate` covers Node 24 CI, the math-escape preservation suite, Vitest, production and synthetic-fixture builds, and the three current Playwright groups. It installs dependencies once with `npm ci`; the disposable agent image has the matching Node 24 and Playwright 1.62.1 browsers preinstalled.
- `jenkins-production-smoke` is separate from the required CI gate. For PRs/main pushes it reports the owner-configured read-only smoke, or reports neutral/not configured. It has no deployment capability or production credentials.
- Each build uses a one-use unprivileged agent with a clean workspace and no Docker socket, controller volume, host mounts, or production secrets. Workspace cleanup runs on both success and failure.

The Jenkins image/profile code is not live qualification. The current checked-in profile does not yet replace the weekly/manual Production Smoke triggers with a controller-owned exact-SHA scheduled/manual job. Keep those Actions triggers active until that job exists, its Check attribution and SHA behavior are tested, and the per-repository owner approves the transition. Do not claim complete workflow migration before then.

## Qualification and cutover

Keep GitHub Actions authoritative. For this repository independently, record the exact PR-head SHA comparisons needed to cover its distinct risk-relevant behaviors, including code and configuration changes, deliberate failure, unauthorized PR denial before checkout, stale heads, cancellation, workspace/container cleanup, check-App attribution, reviewer-readable summaries, and main-push behavior where applicable. Do not repeat equivalent observations to reach a fixed quota. Reuse fresh exact-SHA Actions results; label missing comparisons inconclusive rather than launching unnecessary hosted runs.

Then test host restart/reconnection, backup/restore, and a same-SHA owner-controlled Actions fallback. Read back branch protection before any transition. During a transition require both checks, then remove only the migrated Actions requirement after Jenkins alone has passed and branch protection is read back. Do not alter Vercel or deploy.

## Progress measure

The primary portfolio measure is:

`Jenkins verification coverage = routine eligible verification executions completed by Jenkins / all routine eligible verification executions`

Report it by repository, workflow lane, and trigger type (PR, main push, scheduled, manual). Track owner-triggered Actions fallback and intentionally retained Actions workflows as separate categories. Report GitHub Actions minutes/billing as supplementary information only; it is not a qualification or rollout-success criterion.
