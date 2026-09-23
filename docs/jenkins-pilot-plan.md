# Jenkins CI/CD pilot and decision plan

**Status:** proposal for an Epic; no Jenkins service, GitHub App, branch rule, workflow, or deployment has been changed by this plan.

**Evidence snapshot:** 2026-09-22. Re-read mutable GitHub and host state before implementation.

## Decision to make

Can Jenkins provide a dependable, authoritative PR merge gate for the designated private Setness Consulting site repository, run its standard CI and Cloudflare Candidate checks, and later deploy through the approved release path—while reducing GitHub-hosted Actions usage enough to justify the added service and migration work?

The comparison must include the existing self-hosted GitHub Actions path, not just hosted Actions versus Jenkins. GitHub does not charge Actions minutes for self-hosted runner execution, so Jenkins is not uniquely capable of meeting the minute objective. It would replace the Actions runner integration with a Jenkins controller, GitHub check publishing, Jenkinsfiles, plugin upkeep, credential boundaries, and a new service to operate.

**Recommendation:** time-box an early feasibility and effort comparison, then pilot Jenkins only if it demonstrates a credible advantage on this exact workload. Do not infer target qualification from another repository's successful runner receipt. Do not continue the existing runner only to defend sunk effort, and do not choose Jenkins on the assumption that it will be less work. Compare the remaining work and ongoing cost of both options. Keep the pilot limited to one repository and a reviewable PR; do not start broad fleet adoption or production deployment as part of the first decision.

## Current evidence and caveats

### Target repository

- The existing required check is currently published by GitHub Actions and must be kept until the replacement is proven; the new Jenkins check must be attributed to the intended GitHub App and tied to the exact PR head SHA.
- Before cutover, explicitly decide and read back required reviews, administrator enforcement, and any bypass actors; do not assume a green Jenkins check alone makes the gate authoritative.
- A recent workflow-run sample showed standard CI, Cloudflare Candidate, deployment, and nightly E2E activity. This is a short, high-churn sample—not a monthly forecast or a measure of billed minutes. Per-run elapsed time is also not the billing source of truth. Capture the account's actual Actions usage/billing baseline before comparing savings.
- Fewer Actions minutes do not necessarily mean lower cash spend if the account is within its included allowance. Report minute reduction and actual billed-cost reduction separately.
- Standard CI runs on all PRs and pushes to the default branch. Cloudflare Candidate is path-filtered to the website code and its workflow file, with a manual trigger; it repeats most standard CI steps and adds staging compatibility checks and a deploy dry run. A separate tutor-site workflow, nightly/manual E2E, and a main-branch deployment workflow also exist.
- The first Jenkins scope requested is standard CI plus Cloudflare Candidate. This is not yet a complete disposition of every workflow. Before calling Jenkins the repository-wide authority, explicitly migrate, retain, or retire Tutor Web CI, nightly E2E, and deployment. Any retained Actions minutes must be visible in the comparison.

### Existing self-hosted CI alternative

- The latest live self-hosted-runner pilot receipt qualifies a different API workload; it does not qualify this site repository.
- Target-specific local-runner evidence is still missing for the site's Node builds, Cloudflare Candidate checks, and required-check behavior.
- Therefore, compare the remaining work to qualify this target on the existing runner against the work to stand up Jenkins. Both alternatives need target-specific parity, cleanup, failure, and recovery evidence.

### Host feasibility

- The preferred host is Windows with WSL2 available, but Docker lifecycle, restart recovery, and agent connectivity still need proof. Docker is an option, not an available runtime assumption.
- First test whether the selected runtime reliably starts after Windows restart, retains Jenkins data, and reconnects an isolated Linux agent. If Docker adds brittle lifecycle work, compare running controller and agent services in WSL2 instead. Do not let runtime feasibility become a multi-week prerequisite to deciding whether Jenkins is worthwhile.
- A single Windows host is a single point of failure. Sleep, reboot, network loss, or disk failure must leave the required check pending and block the merge; never auto-pass, fabricate a status, or bypass branch protection to keep work moving.

## Proposed design, subject to a proof of feasibility

1. **Controller:** use the official Jenkins LTS container/image and a pinned, reviewed plugin catalog; manage configuration with Jenkins Configuration as Code. Keep the web UI bound to localhost for the polling pilot. Persist `JENKINS_HOME` in a Linux volume, and prove backup plus restore, including the separately protected encryption key material. Keep controller executors at zero.
2. **Agent:** execute Linux builds under a separate, unprivileged WSL2 identity or isolated agent service with one executor initially. No Docker socket, no controller-home access, no administrator rights, and no shared working directory with the existing CI runner. Test process termination and workspace cleanup after both passing and deliberately failing jobs. If a safe, maintainable boundary cannot be demonstrated on this host, stop the Jenkins pilot rather than weakening it.
3. **GitHub integration:** use GitHub Apps installed only for the pilot repository, not a personal token or organization-wide credential. Keep one app read-only for repository discovery/checkout (likely metadata, contents, and pull-request read permissions) and a separate app for publishing Checks (Checks write plus only the API permissions its plugin demonstrably needs). Do not grant Actions, administration, or branch-protection write permissions. Keep check-write and future deployment credentials on the controller/plugin side; never pass them into PR-controlled shell steps. Test credential visibility with an untrusted PR before any required-check change. Jenkinsfiles execute repository code, so a PR is not “safe” merely because the pipeline is declarative.
4. **Events:** use GitHub polling for the first repository, initially every 2–5 minutes, and measure request rate, scan duration, and PR-to-check latency. Polling avoids a public Jenkins endpoint/webhook requirement but trades freshness for API traffic. Set an explicit API request budget and revisit polling before adding repositories; use a signed, restricted webhook only if measured polling cost or latency fails the agreed target.
5. **Checks:** prove Jenkins can publish a check against the exact PR head SHA and that GitHub attributes it to the intended GitHub App. Use a unique proposed context such as `jenkins-pr-gate`; prefer one required, always-present result that runs standard CI every time and runs Cloudflare Candidate checks for relevant changes, with an explicit, visible “not applicable” result when skipped. If the chosen plugin cannot reliably provide that behavior, settle the check-context/skip design before branch protection changes. Include changes to the Jenkins pipeline itself in the candidate-validation conditions.
6. **Resources and retention:** start at one build at a time, set measured CPU/memory/time limits, and do not share writable build caches across jobs at first. Add only a lockfile-keyed cache after proving it cannot change results or leak files between trust boundaries. Bound build/log retention (proposed starting point: 30 days or 100 builds, whichever comes first) and verify disk usage.

### Security and availability are merge-gate criteria

- Polling does not make a sleeping or disconnected Windows host highly available. Define expected availability and recovery time before declaring Jenkins authoritative.
- PR code can run arbitrary build scripts. A reusable or persistent agent must not retain processes, credentials, or writable state from a prior build. Keep secrets out of standard and Candidate jobs; the Candidate job uses staging configuration and dry-run validation only.
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

- Capture account-level Actions minutes/cost, workflow run counts, PR queue-to-check latency, runner failure rate, and operator time for a representative period.
- Estimate remaining target-specific qualification work for the existing runner from current artifacts; do not reuse another repository's result as target evidence. Set a small engineering-hours cap for the Jenkins runtime spike before starting (one workday is a reasonable proposal); if it cannot be stood up and recovered inside that cap, pause and compare the WSL-native option or continue with the existing runner.
- Prove the chosen runtime survives a Windows restart, preserves controller state, reconnects the isolated agent, and leaves the UI private.
- Record the GitHub App permissions and the expected required-check identity before creating or installing an App.

### 1. Build the target pipeline in shadow mode

- Reproduce the existing standard CI commands on Node 22 and the Cloudflare Candidate checks without production credentials or deployment capability.
- Keep hosted Actions as the current authority. Avoid an open-ended duplicate run on every PR: compare a bounded set of at least ten matching commits/change shapes (source, dependency lockfile, docs-only, CI/Jenkinsfile changes, Cloudflare staging build, and Tutor Web disposition) and include a deliberately failing fixture. For each selected SHA, compare the current hosted result with Jenkins and, where the runner is ready, the existing self-hosted Actions lane. Invoke the self-hosted comparison manually or through a non-required pilot job pinned to that runner; do not add a second GitHub-hosted job just to measure it.
- For each comparison, record source SHA, dependencies/toolchain, outcome, failure fingerprint, duration, cleanup, and any check-SHA mismatch. A green test suite without the right commit/check identity is not parity.
- Stop if results differ without explanation, PR code can access privileged credentials, or agent cleanup/recovery is not proven.

### 2. Cut over the PR gate

- First require both the existing Actions `build-test` and the Jenkins App check tied to the PR head SHA; keep the Actions triggers enabled during this no-gap transition. Remove the Actions app's `build-test` context only after Jenkins has demonstrated reliable success and failure reporting on the targeted PR cases.
- Read back required reviews, administrator enforcement, bypass actors, strictness, and any merge-queue event requirements. Prove docs-only, web changes, pipeline changes, stale heads, failed builds, cancelled builds, and an unavailable Jenkins host all block or report accurately.
- Then disable the migrated Actions PR/push triggers so the gate stops consuming GitHub-hosted minutes. Keep any intentionally retained workflows listed with their expected run frequency and cost; do not leave duplicate workflows silently enabled.
- Record a manual rollback procedure to re-require the hosted Actions check and verify that check on the same SHA. The recovery must be owner-controlled and auditable.

### 3. Deployment and broader adoption (later decision)

- Deployment is a stated long-term requirement, but it is deliberately outside the first gate cutover. Cloudflare is the intended target; preserve the existing fallback until parity and rollback gates close. Re-read the current migration/release authority before designing the deploy job.
- Any later deploy job must be isolated from PR jobs, main-only, serialized, traceable to the exact tested SHA, least-privileged, and independently rollbackable. No production deploy, DNS change, provider switch, or retirement of fallback infrastructure is authorized by this plan.
- Expand beyond the first repository only after the pilot wins the comparison, and qualify each workload, permission set, poll budget, and rollback path separately.

## Comparison and decision rule

Compare three options on the same target scope: hosted GitHub Actions, the existing self-hosted Actions runner, and Jenkins. Report separately:

- **GitHub usage:** actual hosted Actions minutes and spend from billing records, not API run counts or wall-clock duration; remaining hosted workflows must be itemized.
- **Engineering effort:** hours to finish/qualify each route, migrate workflows, and maintain plugins, runner/runtime, credentials, and check integration.
- **Gate quality:** exact-SHA success/failure reporting, required-check reliability, queue-to-result latency, missed/duplicate runs, and safe behavior during host outage.
- **Operations/security:** Windows restart recovery, backup/restore, agent cleanup/isolation, credential exposure tests, polling/API use, disk/resource use, upgrades, and rollback time.
- **Total cost:** local host power/storage and operator time alongside GitHub usage. “Zero Actions minutes” alone is not a Jenkins win if it creates higher maintenance or weaker availability.

**Go with Jenkins only if** it completes the requested checks on the target repo, the check is enforceable and attributable to Jenkins, the outage/security/rollback cases pass, and measured or defensibly forecast total cost/effort is better than extending the existing self-hosted Actions route. Otherwise, close the Jenkins pilot with the evidence and continue the simpler route.

## Candidate first Epic boundary

Create the first Epic only after reviewing this plan. Scope it to baseline/feasibility, target-repo CI and Candidate parity, a bounded shadow pilot, a protected cutover decision, and documented rollback. Keep multi-repository rollout and production deployment as gated follow-on work; preserve deployment as a required future capability, but do not make it an implicit acceptance criterion for the PR-gate pilot.

This plan is stored in a public repository. Keep private repository identifiers, branch-policy snapshots, run-volume details, logs, and credentials out of future public artifacts unless their publication is explicitly reviewed.

## References

- GitHub Actions billing and self-hosted runner charges: [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- GitHub branch protection and required check source: [Protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- GitHub API quotas and limits: [REST API rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
- GitHub App permission selection: [Choosing permissions](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app)
- Jenkins build isolation and untrusted pipeline risks: [Securing builds](https://www.jenkins.io/doc/book/security/securing-builds/), [Controller isolation](https://www.jenkins.io/doc/book/security/controller-isolation/), [Securing organization folders and multibranch pipelines](https://www.jenkins.io/doc/book/security/securing-org-folders-and-multibranch-pipelines/), and [Credentials](https://www.jenkins.io/doc/book/security/credentials/)
- Jenkins pipeline configuration: [Pipeline as Code](https://www.jenkins.io/doc/book/pipeline/pipeline-as-code/) and [Best practices](https://www.jenkins.io/doc/book/using/best-practices/)
