# Portfolio profile contract

The private `project-jenkins-config` catalog is input data, not a pipeline
language. A profile can select only a centrally implemented ID. It cannot
provide shell text, a Jenkinsfile, an agent label, credentials, environment
variables, network policy, or check conclusions.

`integration/portfolio-profile-contract` defines the strict catalog envelope,
the central implementation registry, exact-SHA request resolution, and the
initial same-repository/owner-only PR policy. Its Node 22 adapter is a
contract-tested component; the Jenkins runtime consumer and controller-side
GitHub App token broker must call this contract before a profile is executable.
Do not treat the contract package or catalog installation as proof of live
Jenkins qualification.

The first centrally defined adapter is `node22-foundation-v1`. It uses the
existing `setness-ephemeral` agent class, pinned to Node 22.23.3, and static
argument vectors for `npm ci --ignore-scripts`, `npm run check`, `npm test`, and
`npm run verify`. It rejects a profile whose required Node version does not
exactly match that agent. For example,
`project-github-api`'s current Actions workflow pins Node 22.14.0, so its planned
profile cannot run on this adapter until a matching trusted agent is available.
The target's package scripts are test code, not trusted policy; they must run
only after checkout credentials have been removed and inside the unprivileged
disposable agent. This adapter is not yet wired into a live Jenkins job.

Fork PRs are rejected. An owner allowlist is a bounded shadow policy, not a
sandbox. Do not broaden access or make this check required until the runtime
consumer verifies repository identity and PR-head SHA through GitHub, publishes
Checks from the controller, and proves agent isolation and cleanup.
