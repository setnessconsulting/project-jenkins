# Jenkins CI/CD pilot and decision plan

**Status:** implementation in progress, shadow-only. No target workflow, branch rule, production deployment, or cutover has been changed. See [the local controller runbook](local-controller.md) for the live pilot state.

**Plan baseline:** 2026-09-22. Live pilot evidence through 2026-09-23 is recorded in [the local controller runbook](local-controller.md). Re-read mutable GitHub and host state before each gate.

## Decision to make

Can Jenkins become the normal executor for all verification work across Setness Consulting repositories, including dependable PR checks, scheduled/manual verification, safe recovery, and owner-controlled fallback? Production deployment remains outside Jenkins.

The comparison should include the existing self-hosted GitHub Actions path, but Actions minutes are not the rollout's authority or success metric. The primary measure is Jenkins-owned verification coverage: successful Jenkins check runs divided by eligible verification executions, broken down by repository, workflow lane, and trigger type (PR, main push, scheduled, and manual). Report Actions fallback/residual runs separately. Use exact-SHA parity, safety, availability, recovery, and operating effort to decide whether to widen or cut over.

**Recommendation:** qualify one repository at a time, beginning with Setness Consulting, then use the opt-in profile for the next repository only after the first shadow gates are satisfied. Do not infer target qualification from another repository's successful run. Preserve Actions as the per-repository gate until Jenkins parity and recovery are proven. Do not include production deployment.

## Current evidence and caveats

### Jenkins implementation source

- Review each implementation pull request against its live head SHA, hosted checks, and current review requirements before merging it to `main`; this plan is not approval of unreviewed implementation changes.

### Target repository

- The existing required check is currently published by GitHub Actions and must be kept until the replacement is proven; the new Jenkins check must be attributed to the intended GitHub App and tied to the exact PR head SHA.
- The pilot policy is decided: require the Jenkins App check on the protected branch, enforce the rules for administrators, keep required approvals at zero until an independent reviewer is available, and allow only two privately designated break-glass identities to bypass for PRs. Keep the exact identities and branch-policy snapshot in the private decision record; apply and read back this policy only after the GO gates pass.
- The current pilot lane discovers origin PRs and does not execute fork or outside-contributor code. Keep such PRs on the existing Actions merge path while Jenkins is shadow-only. This is a current execution limit, not a permanent author-based merge policy: before Jenkins becomes a required check for repositories accepting outside contributions, qualify a separate centrally trusted fork lane that checks out the exact fork head using only the minimum read-only access needed, uses central commands on disposable agents without Docker-socket, controller, App-key, write, or deploy access, publishes the exact-SHA result or visible failure from the trusted controller, and proves cleanup and recovery. Never run a PR-controlled Jenkinsfile.
- A recent workflow-run sample showed standard CI, Cloudflare Candidate, deployment, and nightly E2E activity. This is a short, high-churn sample—not a monthly forecast or a measure of billed minutes. Per-run elapsed time is also not the billing source of truth. Capture the account's actual Actions usage/billing baseline before comparing savings.
- The available Actions Usage Metrics view is a partial current-month snapshot, not a complete baseline period. A completed representative period and per-workflow runner/billing details are still required. A hosted Actions job that fails before any step starts is inconclusive for parity, not an application-CI failure.
- Actions minutes and billed cost are secondary operational context only; neither determines whether the Jenkins rollout is succeeding. The primary report is how many eligible verification executions Jenkins handled and which workflow/trigger lanes are covered. Keep deployment and owner-triggered Actions fallback runs separately identified.
- The current workflow inventory includes standard CI, Cloudflare Candidate, a separate tutor-site workflow, nightly/manual E2E, and deployment. Capture exact triggers and path filters in the private Epic/readiness record and re-read them before implementation; the Candidate workflow overlaps much of standard CI and adds staging compatibility checks and a deploy dry run.
- The Setness rollout target is all verification: standard CI, Cloudflare Candidate, Tutor Web CI, and scheduled/manual E2E. Tutor Web and E2E are separate trusted Jenkins lanes with their own toolchains and acceptance evidence. Production deployment remains manual and outside Jenkins; any residual Actions workflow must be explicitly identified in the comparison.

### Existing self-hosted CI alternative

- Evidence from another workload cannot qualify this site repository. Require target-specific evidence for Node builds, Cloudflare Candidate checks, and required-check behavior before treating either self-hosted option as ready.
- Compare the remaining work to qualify this target on the existing runner against the work to stand up Jenkins. Both alternatives need target-specific parity, cleanup, failure, and recovery evidence.

### Host feasibility

- The selected host is the existing Windows machine, with Docker Compose for the controller and an isolated Linux agent on a private Compose network. Initial controller startup, loopback-only UI binding, and agent connection have been demonstrated; Windows restart recovery, backup/restore, and the full agent boundary have not.
- Keep the feasibility spike within the one-workday cap. Prove the chosen Docker runtime reliably starts after Windows restart, retains Jenkins data, restores the protected encryption material, and reconnects the isolated agent. Do not silently expand to a WSL2 redesign; if this path cannot meet the cap and safety criteria, record NO-GO.
- A single Windows host is a single point of failure. Sleep, reboot, network loss, or disk failure must leave the required check pending and block the merge; never auto-pass, fabricate a status, or bypass branch protection to keep work moving.

## Proposed design, subject to a proof of feasibility

1. **Controller:** use the official Jenkins LTS container/image and a pinned, reviewed plugin catalog; manage configuration with Jenkins Configuration as Code. Keep the web UI bound to localhost for the polling pilot. Persist `JENKINS_HOME` in a Linux volume, and prove backup plus restore, including the separately protected encryption key material. Keep one built-in controller executor so trusted controller stages (Test Platform Authorize and Finalize on label built-in) can run after a CasC reload; do not raise it further, and do not schedule repository work on the controller.
2. **Agent:** execute Linux builds in one unprivileged Docker agent on the private Compose network, with one executor initially. No Docker socket, host mounts, controller-home access, administrator rights, or shared working directory with the existing CI runner. Test process termination and workspace cleanup after passing, failing, canceled, and stale-head builds. Container isolation is not a VM boundary: the inbound-agent secret is readable to code running as the agent user, so prove the residual risk is acceptable or replace the agent with disposable isolation before cutover.
3. **GitHub integration:** use one GitHub App installed only for the pilot repository, not a personal token or organization-wide credential. The App has Metadata read, Contents read, Pull requests read, and Checks read/write; it has no Actions, administration, or branch-protection write permission. The GitHub Checks plugin reuses the Branch Source credential, so keep that credential controller-side for repository discovery and check publication. Give the build agent a separate repository-scoped read-only SSH deploy key for checkout, through the Branch Source `SSHCheckoutTrait`, and pin GitHub's published SSH host keys. Do not configure the App credential for agent checkout or pass check-write and future deployment credentials into PR-controlled shell steps. Test credential visibility before any required-check change. Jenkinsfiles execute repository code, so a PR is not “safe” merely because the pipeline is declarative.
4. **Events:** use GitHub polling for the first repository, initially every 2–5 minutes, and measure request rate, scan duration, and PR-to-check latency. Polling avoids a public Jenkins endpoint/webhook requirement but trades freshness for API traffic. Set an explicit API request budget and revisit polling before adding repositories; use a signed, restricted webhook only if measured polling cost or latency fails the agreed target.
5. **Checks:** prove Jenkins can publish a check against the exact PR head SHA and that GitHub attributes it to the intended GitHub App. Configure the required primary check and any separate candidate result through ignored local runtime configuration; do not commit private check contexts. The primary check runs standard CI every time, while the candidate suite runs only for relevant changes and reports an explicit visible “not applicable” result otherwise. Reviewer output must show which suites ran and whether they passed, failed, were canceled, or were not applicable. Verify the rendered output on a PR before changing branch protection. Include changes to the Jenkins pipeline itself in candidate-validation conditions.
6. **Resources and retention:** start at one build at a time, set measured CPU/memory/time limits, and do not share writable build caches across jobs at first. Add only a lockfile-keyed cache after proving it cannot change results or leak files between trust boundaries. Bound build/log retention (proposed starting point: 30 days or 100 builds, whichever comes first) and verify disk usage.

### Security and availability are merge-gate criteria

- Polling does not make a sleeping or disconnected Windows host highly available. Define expected availability and recovery time before declaring Jenkins authoritative.
- PR code can run arbitrary build scripts. A reusable or persistent agent must not retain processes, credentials, or writable state from a prior build. Keep secrets out of standard and Candidate jobs; the Candidate job uses staging configuration and dry-run validation only.
- The repository-scoped read-only SSH key is used during agent checkout. Verify that PR shell steps cannot recover it from temporary files, process state, or the SSH client; otherwise treat it as exposed and replace the checkout boundary before cutover. The inbound-agent secret is likewise readable to code running as that agent user.
- The agent needs package-registry access, but should not inherit Windows credentials or unrestricted access to private LAN services. Prove the chosen network boundary and deny access to controller/admin ports; document any unavoidable egress rather than assuming “no token” means “no exposure.”
- If Jenkins is unavailable, the check remains pending. A documented, owner-controlled recovery may temporarily restore the hosted check as required only after the Actions path passes on the same SHA and branch rules are read back. No auto-fail-open or admin bypass is part of the design.
- Do not place tokens, encrypted secret blobs, private logs, or credentials in this public repository. JCasC may describe credential IDs and wiring, never secret values.

## Reuse from open-source projects

Prefer small, maintained upstream building blocks and pin versions after checking current release/security status. Do not adopt a large third-party “production Jenkins” template without a full review of its license, maintenance, exposed ports, credential model, and Docker-socket use.

| Upstream project | Reuse for | Constraint |
| --- | --- | --- |
| [jenkinsci/docker](https://github.com/jenkinsci/docker) | Official Jenkins controller image and container conventions | Pin an LTS image digest/tag; do not use floating `latest` in the eventual deployment. |
| [configuration-as-code-plugin](https://github.com/jenkinsci/configuration-as-code-plugin) | Declarative controller configuration | Does not install plugins or safely store secret values in this public repository. |
| [plugin-installation-manager-tool](https://github.com/jenkinsci/plugin-installation-manager-tool) | Reproducible plugin installation and dependency resolution | Pin versions; review advisories before updates. |
| [github-branch-source-plugin](https://github.com/jenkinsci/github-branch-source-plugin) | Multibranch PR discovery and repository integration | Restrict discovery to the pilot repo; test behavior for PR-controlled Jenkinsfiles and credentials. |
| [github-checks-plugin](https://github.com/jenkinsci/github-checks-plugin) | Publish GitHub Checks | Validate the app identity, exact PR head SHA, skipped stages, and required-check source end to end. |
| [pipeline-model-definition-plugin](https://github.com/jenkinsci/pipeline-model-definition-plugin) and [credentials-binding-plugin](https://github.com/jenkinsci/credentials-binding-plugin) | Declarative pipelines and narrowly scoped credential binding | Keep pipeline code unprivileged; do not bind check-write or deploy credentials into untrusted PR jobs. |

Use the plugins as components, not as a substitute for the security/availability design. Jenkinsfile Runner is not a Jenkins controller; Kubernetes/Helm and broad third-party templates are unnecessary for this single-host pilot.

## Pilot stages and exit gates

### 0. Baseline and feasibility spike

- Capture Jenkins run counts and coverage by repository/workflow/trigger, exact-SHA/check-source correctness, PR queue-to-check latency, runner failure rate, recovery results, and operator time. Actions minutes/cost may be recorded as supplementary context but are not a GO/NO-GO criterion.
- Estimate remaining target-specific qualification work for the existing runner from current artifacts; do not reuse another repository's result as target evidence. The Docker feasibility cap is one workday; if startup, restart recovery, state restore, and isolated-agent reconnection cannot be proven inside it, record NO-GO instead of extending setup.
- Prove the chosen runtime survives a Windows restart, preserves controller state, restores both Jenkins home and separately protected encryption material, reconnects the isolated agent, and leaves the UI private.
- Read back that the GitHub App is installed only on the pilot repository with the least required permissions, and record the expected required-check identity before enabling discovery or publishing checks.

### 1. Build the target pipeline in shadow mode

- Reproduce the existing standard CI commands on Node 22 and the Cloudflare Candidate checks without production credentials or deployment capability.
- Keep hosted Actions as the current authority. Avoid an open-ended duplicate run on every PR: compare distinct exact-SHA cases that cover the risk-relevant change shapes (source, dependency lockfile, docs-only, CI/Jenkinsfile changes, Cloudflare staging build, and Tutor Web disposition) and include a deliberately failing fixture. For each selected SHA, compare the current hosted result with Jenkins and, where the runner is ready, the existing self-hosted Actions lane. Invoke the self-hosted comparison manually or through a non-required pilot job pinned to that runner; do not add a second GitHub-hosted job just to measure it.
- For each comparison, record source SHA, dependencies/toolchain, outcome, failure fingerprint, duration, cleanup, and any check-SHA mismatch. A green test suite without the right commit/check identity is not parity.
- Do not count an Actions run as a comparator when the job never started or did not complete. Do not launch duplicate hosted runs only to populate the matrix; reuse fresh exact-revision results or mark the case inconclusive and seek owner approval for any narrowly targeted rerun.
- Stop if results differ without explanation, PR code can access privileged credentials, or agent cleanup/recovery is not proven.

### 2. Cut over the PR gate

- First require both the existing Actions check and the Jenkins App check tied to the PR head SHA; keep the Actions triggers enabled during this no-gap transition. Remove the Actions check only after Jenkins has demonstrated reliable success and failure reporting on the targeted PR cases.
- Read back required reviews, administrator enforcement, the two privately designated PR-only bypass actors, strictness, and any merge-queue event requirements. Keep approvals at zero until an independent reviewer is available. Keep direct forks on the Actions merge path during this pilot; do not require contributors to rewrite their PRs as owner-authored branches. Before Jenkins alone becomes required for a repository accepting outside contributions, qualify the separate central fork lane described above. Prove docs-only, web changes, pipeline changes, stale heads, failed builds, canceled builds, and an unavailable Jenkins host all block or report accurately.
- Then disable only the migrated Actions PR/push triggers after Jenkins is required and verified. Keep any intentionally retained or fallback workflows itemized by purpose and run count; do not leave duplicate routine workflows silently enabled.
- Record a manual rollback procedure to re-require the hosted Actions check and verify that check on the same SHA. The recovery must be owner-controlled and auditable.

### 3. Deployment and broader adoption (later decision)

- Production deployment remains outside this pilot. Preserve manual Vercel dispatch; pause its automatic trigger only in the authorized cutover sequence after GO, and do not deploy. Any future Cloudflare deployment is a separate, explicitly approved decision; re-read release authority before designing it.
- Any later deploy job must be isolated from PR jobs, main-only, serialized, traceable to the exact tested SHA, least-privileged, and independently rollbackable. No production deploy, DNS change, provider switch, or retirement of fallback infrastructure is authorized by this plan.
- Expand beyond the first repository only after the pilot wins the comparison, and qualify each workload, permission set, poll budget, and rollback path separately.

## Remaining work to complete all CI/CD for the pilot repository

“All CI/CD moved” means every current workflow has an explicit Jenkins, retained-Actions, or retired disposition; no old and new triggers run unnoticed in parallel; and failures, outages, recovery, and release authority are documented and tested. It does not mean enabling a production deploy in this pilot. The Jenkins-vs-existing-self-hosted-Actions GO decision remains the first gate; if Jenkins loses on effort, reliability, or total cost, stop here and finish the simpler route.

| Order | Work remaining | Exit evidence |
| --- | --- | --- |
| 1. Harden the pilot gate | Rerun the corrected centrally defined Jenkins pipeline. The owner waived the fixed ten-observation-per-profile quota on 2026-10-01; cover each applicable risk behavior and change scope without a minimum run count. Include exact-head success across source, lockfile, documentation-only, pipeline/configuration, and Candidate-relevant changes; deliberate command failure; stale-head rejection; denied-author pre-checkout reporting; Candidate not-applicable behavior; cancellation or outage cleanup followed by fresh-run recovery; and reviewer-visible check attribution. Record each PR-head SHA plus the base and actual tested merge revision at the time of each run. Reuse an existing required Actions result only when it is fresh and tested on the same revision; do not trigger extra hosted Actions runs to fill a count. Prefer the qualified target-specific self-hosted Actions route for comparisons. If neither source has a fresh matching result, mark the case inconclusive and obtain owner approval before a narrowly targeted hosted rerun. Treat stale, timed-out, canceled, pre-step, or incomplete results as inconclusive, not parity. Include marker-file deletion and Candidate-stage skip where applicable. | Every observed result matches a fresh, revision-matched comparator or has an explained, accepted difference; the primary check never passes if classification is unknown or a relevant Candidate suite did not finish. The combined GitHub Check output is useful to reviewers. Policy self-tests and source contract pass. |
| 2. Prove operations and isolation | Rehearse backup and restore of the complete Jenkins home plus separately protected encryption material. Test Windows restart, Docker Desktop startup, controller/agent reconnection, host outage, disk pressure, retention, cancellation, and workspace cleanup. Decide whether the persistent agent-secret/network boundary is acceptable or replace it with disposable isolated agents. | Measured recovery time meets an owner-approved target; state and credentials restore; the UI remains private; unavailable Jenkins leaves checks pending; no build can access production credentials or protected controller state. |
| 3. Confirm Jenkins workload coverage and effort | Count eligible verification executions and Jenkins-completed checks by repository, workflow lane, and trigger type; separately identify Actions fallback/residual executions. Estimate remaining work for the existing self-hosted Actions route and Jenkins operating effort. | Evidence-backed GO/NO-GO from exact-SHA parity, safe operation/recovery, fallback, workflow coverage, and sustainable operator effort. Actions-minute totals are supplementary and cannot override the Jenkins coverage evidence. |
| 4. Migrate every CI workflow | First migrate standard PR and main-push CI plus Candidate checks with a dual-gate period. Keep Tutor Web CI and scheduled/manual E2E as separately measured Actions residuals until qualified. Pause the automatic Vercel release trigger only in the authorized cutover sequence; preserve manual dispatch and do not deploy. Keep intentional Actions workflows enabled until each Jenkins equivalent passes on matching revisions. | Workflow inventory has a signed-off Jenkins/Actions/retired disposition, equivalent triggers and path behavior, exact-SHA results, operator ownership, and no unintended duplicate runs. |
| 5. Complete release/deployment design | Production deployment is deferred. Any future Jenkins release job must be main-only, serialized, separately approved, isolated from PR jobs, use least-privilege credentials unavailable to PR jobs, carry exact tested-SHA provenance, and have health checks and tested rollback. | Separate release acceptance and explicit owner authorization. No production deployment, provider switch, DNS change, or fallback retirement is implied by the CI-gate pilot. |
| 6. Cut over and measure | Read back required reviews, check source/name, strictness, administrator enforcement, the two privately designated PR-only bypass actors, and merge-queue behavior. Keep approvals at zero until an independent reviewer is available. Grant the second designated identity only the minimum access needed for its bypass at cutover; keep exact identities and policy snapshots private. Require both old and Jenkins checks during transition. Exercise the owner-controlled same-SHA Actions fallback; then remove only the migrated requirements and disable only the corresponding routine triggers. | Jenkins owns the intended routine verification lanes with no fail-open path; policy is enforceable, rollback is practiced, and remaining Actions runs are explicitly classified as fallback or residual. Report hosted minutes only as supplementary information. |

The public repository keeps target owner/name, marker file, Candidate path rules, and installed App ID in the ignored local `.env`; do not copy those values into public plan text or examples. This configuration boundary does not replace a separate CI process for validating changes to this Jenkins repository itself.

## Comparison and decision rule

Compare hosted GitHub Actions, the existing self-hosted Actions runner, and Jenkins on the same verification scope. Report separately:

- **Jenkins coverage (primary):** Jenkins-owned completed verification runs divided by all eligible verification executions, broken down by repository, workflow lane, and trigger. Keep fallback and residual Actions runs separate.
- **GitHub usage (secondary):** billable hosted minutes, total Actions run counts, and spend for context; these do not determine rollout success.
- **Engineering effort:** hours to finish/qualify each route, migrate workflows, and maintain plugins, runner/runtime, credentials, and check integration.
- **Gate quality:** exact-SHA success/failure reporting, required-check reliability, queue-to-result latency, missed/duplicate runs, and safe behavior during host outage.
- **Operations/security:** Windows restart recovery, backup/restore, agent cleanup/isolation, credential exposure tests, polling/API use, disk/resource use, upgrades, and rollback time.
- **Total effort and operations:** local host power/storage, operator time, plugin upkeep, recovery, availability, and integration maintenance. A high Jenkins run count is not a win if safety, check reliability, or maintainability is poor.

**Expand/cut over only if** Jenkins completes the intended verification lanes, check attribution and exact-SHA behavior are correct, isolation/recovery/fallback pass, and the service can be operated sustainably. Jenkins coverage is the primary progress metric; Actions billing does not override these gates. If a lane is unsafe or unavailable, keep that lane on Actions until fixed.

## Jira tracking boundary

The implementation Epic and child issues are tracked separately in Jira. This public plan records the technical decision gates, not the private issue keys or target-repository evidence. Keep multi-repository rollout and production deployment as gated follow-on work; neither is an implicit acceptance criterion for this PR-gate pilot.

This plan is stored in a public repository. Keep private repository identifiers, branch-policy snapshots, exact workflow triggers, run-volume details, logs, and credentials out of future public artifacts unless their publication is explicitly reviewed.

## References

- GitHub Actions billing and self-hosted runner charges: [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- GitHub branch protection and required check source: [Protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- GitHub API quotas and limits: [REST API rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
- GitHub App permission selection: [Choosing permissions](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app)
- Jenkins build isolation and untrusted pipeline risks: [Securing builds](https://www.jenkins.io/doc/book/security/securing-builds/), [Controller isolation](https://www.jenkins.io/doc/book/security/controller-isolation/), [Securing organization folders and multibranch pipelines](https://www.jenkins.io/doc/book/security/securing-org-folders-and-multibranch-pipelines/), and [Credentials](https://www.jenkins.io/doc/book/security/credentials/)
- Jenkins pipeline configuration: [Pipeline as Code](https://www.jenkins.io/doc/book/pipeline/pipeline-as-code/) and [Best practices](https://www.jenkins.io/doc/book/using/best-practices/)
