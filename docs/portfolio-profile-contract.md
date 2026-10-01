# Portfolio profile contract

The private profile catalog is input data, not a pipeline language. A profile
can select only a centrally implemented ID. It cannot
provide shell text, a Jenkinsfile, an agent label, credentials, environment
variables, network policy, or check conclusions.

`integration/portfolio-profile-contract` defines the strict catalog envelope,
the central implementation registry, exact-SHA request resolution, and the
initial same-repository/owner-only PR policy. Its Node 22 adapter is a
contract-tested component. The manual
`portfolio-dispatch/portfolio-pr-gate` invokes it from the controller after
reading the private catalog and refreshing the live PR. A separate,
disabled-by-default controller poller can discover exact-SHA PR work only
after the private control plane is explicitly active and a profile selects an
implementation admitted by the central routine-dispatch allowlist.
This does not make a repository Jenkins-authoritative or qualify its profile.

For portfolio pull-request dispatch, use
`resolveAuthorizedShadowPullRequestForRepository` as the single entry point. It
selects the profile from the verified repository identity, then verifies the
open same-repository PR, allowlisted author, and exact current head SHA before
returning any command vectors. Do not accept a profile ID independently from
the SCM repository or call the lower-level PR verifier and profile resolver
separately in Jenkins orchestration code.

The first centrally defined adapter is `node22-foundation-v1`. It uses the
existing `setness-ephemeral` agent class, pinned to Node 22.23.3, and static
argument vectors for `npm ci --ignore-scripts`, `npm run check`, `npm test`, and
`npm run verify`. It rejects a profile whose required Node version does not
exactly match that agent. A profile pinned to a different Node patch must remain
planned until a matching trusted agent is available or its repository's CI
baseline is deliberately updated and verified.

The `python312-test-platform-v1` implementation uses a dedicated one-build,
unprivileged agent with Python 3.12.14 built from the official source archive
whose SHA-256 is pinned in `agent/Python312.Dockerfile`. Its centrally-owned
argument vectors install the repository's development extra and run
`python -m test_platform.verify`. The private profile records the descriptive
`requiredPythonVersion` pin; it cannot provide a Python command, image, label,
or environment value. This implementation matches only the single Linux
verification job in `project-test-platform`; it does not cover unrelated
repositories or workflows that use another Python version, operating system,
matrix, or additional verification jobs.

The `python312-cloudflare-api-uv-v1` implementation uses the same dedicated
Python 3.12.14 agent and centrally owned command vectors to install pinned
`uv==0.11.17`, synchronize the locked development environment, run
`scripts/verify.py`, and run `cloudflare-api doctor --json`. It maps only the
pull-request job from the repository's primary workflow; its self-hosted,
scheduled, release, and manual workflows remain in Actions.

The five additional first-wave implementations—`python312-blender-api-v1`,
`python312-fmod-api-v1`, `python312-game-maker-v1`,
`python312-context-file-maker-v1`, and `python312-cpa-ai-pack-v1`—also use the
dedicated Python 3.12.14 agent and fixed commands from this resolver. They are
partial supplemental shadows: Python 3.11 matrices, Windows-specific checks,
Gitleaks, path filters, and event-specific behavior remain in Actions as
documented in `python312-first-wave-remaining-2026-09-30.md`. None is added to
routine polling, and none permits Jenkins cutover.

The focused shadow set includes six centrally trusted lanes:

- `python312-test-platform-v1` runs the existing single Linux verification job
  on Python 3.12.14. The dedicated Test Platform agent also exposes the Docker
  socket for that repository's Docker-backed verification; this is limited to
  the protected pilot VM and remains an owner-only shadow boundary.
- `node24-game-platform-sdk-v1` runs `npm ci`, `npm run verify`, and
  `npm run verify:bundle` on Node 24.21.0. It covers the repository's PR
  verification workflow; artifact upload remains an Actions-only reporting
  step.
- `python312-portfolio-graph-uv-v1` installs pinned `uv==0.11.17`, syncs the
  lockfile, and runs the verification script and CLI checks on Python 3.12.14.
  It covers only the Ubuntu/Python 3.12 cell of the existing 2-by-2 OS/runtime
  matrix. Windows and Python 3.13 remain Actions coverage.
- `node24-curiouspathway-pilot-v1` runs the CI typecheck, lint, unit suites,
  builds, and three Playwright PR groups on Node 24.21.0. The disposable image
  preinstalls Playwright 1.62.1 and Chromium, Firefox, and WebKit, matching the
  target lockfile and replacing the workflow's browser-install step. The
  production smoke workflow and owner-only Windows local verification remain
  Actions work.
- `node2214-vercel-api-gitleaks-v1` combines the repository's Gitleaks and
  Node.js verification jobs under one centrally trusted PR check. It uses the
  pinned Node 22.14.0/Gitleaks agent and leaves push/manual triggers, Actions
  authority, and deployment behavior unchanged.
- `jenkins-repository-contract` runs the centrally defined Node contract suites
  against the current exact PR head of `project-jenkins`: the four portfolio
  profile-contract Node test files and the Test Platform adapter test. Its
  existing private profile is `project-jenkins-self-check`, still shadow-only
  at 0/4; the suite does not deploy or change Actions authority.

`project-setness-consulting` is already observed through its separate
centrally-owned repository pilot; it is not sent through the portfolio
dispatcher and its Actions checks remain authoritative. Its candidate,
Tutor Web, scheduled E2E, and deployment/release workflows remain separate
coverage and must be mapped before any cutover.

The `node22-verify-clean-checkout-v1` implementation uses a separate one-use
agent pinned to Node 22.14.0/npm 10.9.2 and the static argument vectors
`npm ci`, `npm run verify`, and `npm run verify:clean-checkout`. It exists for
repositories whose reviewed CI contract requires that exact runtime and
command sequence; repository-specific profiles remain private and planned
until the live Jenkins consumer and exact-SHA qualification are complete.
Repository-specific profile details belong in the private catalog, not this
public repository. Target package scripts are test code, not trusted policy;
they must run only after checkout credentials have been removed and inside
the unprivileged disposable agent. The controller dispatcher allowlists the
centrally implemented Node 22.14 clean-checkout implementation. Catalog
profiles remain `planned` until the matching runtime is loaded and ready and
the private catalog explicitly moves an individual repository profile to
shadow. Existing pilot jobs remain separate and are not routed through this
dispatcher, avoiding duplicate check publishers. The dispatcher is disabled
when its private catalog setting is absent, and the former root-level job is
explicitly disabled to prevent stale definitions from surviving reconfiguration.

Temporary read-only checkout tokens are stored only in the folder-scoped
credentials store of the dedicated `portfolio-dispatch` folder, whose only
jobs are the centrally trusted dispatcher and credential reaper. The token is
removed after checkout and in failure cleanup; a dedicated reaper runs every
15 minutes and removes matching credentials older than 65 minutes. If a failed
store write cannot be rolled back, the error is sanitized and the token's
one-hour expiry plus scheduled retry bound the recovery window. The folder
store is selected by exact folder context; the controller-wide System
credentials store is never used for checkout tokens.

The poller is opt-in through the ignored local
`JENKINS_PORTFOLIO_PR_POLL_ENABLED` setting, which defaults to `false`, and
also requires the private catalog location and `controlPlane.status: active`.
Routine dispatch is restricted in trusted code to
`project-test-platform`, `project-game-platform-sdk`, `curiouspathway`,
`project-portfolio-graph`, `project-vercel-api`, and `project-jenkins`, with
only their six exact implementation/repository pairs. The Jenkins repository
pair uses the already approved `jenkins-repository-contract` implementation;
the poller's same-repository, non-draft, owner-only and exact-live-head checks
remain unchanged.
`project-setness-consulting` uses its separate pilot. The poller checks only
open, same-repository, non-draft PRs authored by `setnessconsulting`, queues
one exact-head SHA at a time, and persists dispatch state in Jenkins home. It
does not schedule main-branch, fork, or outside-author verification. The
reaper schedule remains maintenance-only. Enabling this poller does not make
a repository Jenkins-authoritative; Actions, protection, and deployment
settings remain unchanged until separately qualified and approved.

Exact-SHA qualification uses a profile-specific evidence matrix instead of a
fixed observation quota. Each case must exercise a distinct required behavior
for that repository and lane; counts alone are not evidence. A profile cannot
claim qualification until every case in its recorded matrix passes and its
separate isolation, cleanup/recovery, fallback, and owner-approved protection
requirements are met.
The trusted resolver also pins the required case count to the centrally
reviewed implementation matrix (four standard cases, five Game AI cases, or
six Vercel API cases), so catalog data cannot shrink a profile to a one-run
qualification.

Fork PRs are rejected. An owner allowlist is a bounded shadow policy, not a
sandbox. Do not broaden access or make this check required until the runtime
consumer verifies repository identity and PR-head SHA through GitHub, publishes
Checks from the controller, and proves agent isolation and cleanup.
