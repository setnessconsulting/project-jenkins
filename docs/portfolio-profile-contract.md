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

The `python312-jira-admin-uv-v1` implementation uses that same dedicated
Python 3.12.14 agent to install pinned `uv==0.11.17`, sync the locked
development extra, run the repository's tests and compile check, verify the
environment, audit dependencies, scan for secrets, and verify a clean
checkout. It maps only the credential-free `project-jira-admin` CI job;
Actions keeps the required `test` check, path filters, push coverage, and
fallback authority.

Four additional first-wave implementations—`python312-blender-api-v1`,
`python312-fmod-api-v1`, `python312-context-file-maker-v1`, and
`python312-cpa-ai-pack-v1`—use the dedicated Python 3.12.14 agent and fixed
commands from this resolver. Their supplemental shadows leave Python 3.11
matrices, Windows-specific checks, Gitleaks, path filters, and event-specific
behavior in Actions as documented in
`python312-first-wave-remaining-2026-09-30.md`.

`python312-game-maker-v1` is bound in trusted code to the exact
`project-game-maker-python312` profile and `setnessconsulting/project-game-maker`
repository. Its fixed plan runs the complete workflow command sequence first
with Python 3.11.17, then with Python 3.12.14, including pip upgrade, editable
development install, Ruff, mypy, pytest, CLI checks, and a clean-tree assertion
for each runtime. The dedicated unprivileged image is built from the official
Python source archives whose SHA-256 values are pinned in
`agent/GameMakerPythonMatrix.Dockerfile`; it exposes no credentials, Docker
socket, or controller access. The target workflow's `setup-python` selects the
floating `3.11` patch, while this agent pins Python 3.11.17; the observed
same-head Actions run used Python 3.11.16. That patch difference prevents a
runtime-parity claim. Actions remains authoritative and keeps its push trigger.
This PR adds centrally trusted code and image build support; the image must be
built and deployed on the Jenkins VM before any actual Jenkins Game Maker run.
The profile's qualification record remains 1/4 exact-SHA cases.

The trusted poller allowlist includes Blender, FMOD, and Game Maker for routine
shadow dispatch when enabled. Context File Maker and CPA AI Pack remain manual
because the poller does not implement their Actions path filters; Context File
Maker also has a separately conditioned Windows lane.

The focused central implementation set below describes reviewed code support;
it does not mean a private profile is enabled, qualified, or authoritative:

- `python312-test-platform-v1` runs the existing single Linux verification job
  on Python 3.12.14. That lane is Python-only: no agent receives the guest
  Docker socket, so the repository's Docker-backed verification stays in
  Actions rather than pretending to run here.
- `node24-game-platform-sdk-v1` runs `npm ci`, `npm run verify`, and
  `npm run verify:bundle` on Node 24.21.0. It covers the repository's PR
  verification workflow; artifact upload remains an Actions-only reporting
  step.
- `node24-game-planetary-survey-v1` runs the
  `Game-Planetary-Survey` `verify` job's exact `npm ci` and
  `npm run verify` commands on Node 24.21.0. It covers only the static, unit,
  and build job in `.github/workflows/ci.yml`. The downstream three-engine
  Playwright suites, nested host checks, and failure-artifact upload remain in
  Actions, and the workflow's `workflow_dispatch` trigger remains intact.
  This implementation alone does not enable a private profile, qualify the
  lane, or change Actions authority.
- `node24-game-math-detective-static-v1` maps the credential-free static part
  of `game-math-detective`'s verification workflow. It runs `npm ci`,
  typecheck, lint, unit tests, the standalone boundary guard, and the non-root
  build-base check on Node 24.21.0. The Chromium install, Phaser renderer,
  accessibility, and browser E2E lanes remain in Actions because they require
  the repository's browser runtime and artifact behavior. Actions remains
  authoritative and the profile is shadow-only at 0/4.
- `node24-game-motion-lab-static-v1` maps the credential-free static part of
  `game-motion-lab`'s `verify` workflow. It runs the contract and foundation
  checks, typecheck, lint, unit tests, build, release-manifest readback, and
  bundle-budget check on Node 24.21.0. Playwright browser lanes, nested host
  verification, Lighthouse capture, and performance artifact upload remain in
  Actions. Actions remains authoritative and the profile is shadow-only at 0/4.
- `node24-game-ecosystem-rescue-static-v1` maps the credential-free static part
  of `game-ecosystem-rescue`'s verification workflow. It runs install,
  typecheck, lint, unit tests, boundary, deterministic-randomness, link,
  build-base, production-build, and bundle-budget checks on Node 24.21.0.
  Chromium and Playwright smoke/accessibility lanes, trace uploads, and the
  manual release candidate/R2 path remain in Actions. Actions remains
  authoritative and the profile is shadow-only at 0/4.
- `node24-game-fraction-match-full-ci-v1` is bound to the exact profile
  `game-fraction-match-node24-full-ci` and repository
  `setnessconsulting/game-fraction-match`. It runs the complete Linux verify
  sequence—`npm ci`, typecheck, lint, coverage tests, architecture checks,
  production build, and privacy check—before the direct and nested Playwright
  host suites. The one-use `secondary-node24-playwright-ephemeral` worker keeps
  the build and coverage output from that SHA in the same workspace for both
  suites. Its centrally installed image provides Node 24.21.0, Playwright
  1.62.1, Chromium, Firefox, WebKit, and their system dependencies; no target
  Jenkinsfile, Docker socket, deployment credential, or command-time GitHub
  credential is exposed to the worker. The trusted gate archives the fixed
  `dist/`, coverage summary and lcov, test-results, and both Playwright report
  paths before workspace cleanup, including after command failures. Jenkins
  artifact retention has not been verified to match the Actions workflow's
  30-day retention. The target pins `@playwright/test` 1.62.1, but its lockfile
  also contains a separate top-level peer `playwright-core` 1.63.0 entry; its
  `.nvmrc` and package engine select Node 24 as a floating major while this
  worker pins 24.21.0. These differences prevent a runtime-parity claim. The
  lane remains a supplemental shadow: GitHub Actions remains authoritative,
  with its `main`/`codex/**` push, pull-request, and manual triggers, 30-day
  uploads, same-repository owner-only author policy, and deployment controls
  unchanged. No cutover or CI-savings claim is made, and the profile remains
  at 0/4 exact-SHA qualification cases.
- `python312-jira-admin-uv-v1` runs `project-jira-admin`'s locked Python 3.12
  verification sequence on the disposable Python agent. It does not read
  Jira credentials, call the live Jira adapter, mutate Jira, or deploy; the
  repository's required Actions `test` check and push/PR path filters remain
  authoritative.
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
  pinned Node 22.14.0/npm 10.9.2/Gitleaks 8.24.3 disposable agent with no Docker
  CLI, socket, or host mounts. Its commands match the live workflow order;
  push/manual triggers, Actions authority, and deployment behavior remain
  unchanged.
- `node2214-unity-api-maintenance-v1` maps only
  `setnessconsulting/project-unity-api`'s repository-only maintenance workflow.
  It uses the existing one-use, no-socket Node 22.14.0/npm 10.9.2 disposable
  agent and runs the fixed `npm ci` then `npm run maintenance` command plan.
  This partial PR shadow reports `jenkins-pr-gate`; GitHub Actions keeps all
  workflow triggers and remains authoritative. The tag-based `release.yml`
  workflow, including its `contents:write` publishing job, stays in Actions.
  This central implementation neither enables nor qualifies its private
  catalog profile, changes target protection, nor grants Jenkins release or
  deployment credentials. The existing same-repository owner-only policy is
  unchanged.
- `node22-verify-clean-checkout-v1` uses the same no-socket Node 22.14.0/npm
  10.9.2 image for `project-jira-api`'s `npm ci`, `npm run verify`, and
  `npm run verify:clean-checkout` commands. Its exact repository/profile pair
  is included in the central allowlist for owner-only shadow polling when the
  poller is enabled. The required Actions `verify` check, push/manual triggers,
  and token-backed exact-SHA manual fallback remain in Actions; Jenkins receives
  no GitHub write token.
- `node22-github-api-foundation-v1` runs `project-github-api`'s existing Node
  22.23.3/npm 10.9.9 command sequence on the no-socket Setness Node/PowerShell
  agent. Its push, pull-request, and manual Actions triggers remain intact;
  qualification stays at 0/4.
- `node22-investment-council-v1` maps only the credential-free verification job
  in `project-investment-council`'s `council-check.yml`. On the existing
  no-socket Node 22.23.3/npm 10.9.9 worker it runs the structural check, the
  default dry route, the repository's Node test glob, and its smoke benchmark.
  The workflow's Ubuntu/Windows matrix remains in Actions, as do its push and
  pull-request triggers; this supplemental shadow does not access provider
  credentials, deploy, or change the repository's authority boundary.
- `node22-supabase-api-v1` maps only the Node 22.23.3 cell of
  `project-supabase-api`'s hosted CI matrix. It runs the exact `npm ci
  --omit=optional` and `npm run verify` commands on the no-socket Node 22
  worker. Node 20 and 24, the Python 3.12/3.13 matrix, and the optional
  Windows lane remain in Actions; the repository's `master` branch has no
  protection at this readback, so this supplemental lane is shadow-only.
- `node22-rive-api-v1` maps only the Node 22.23.3 cell of
  `project-rive-api`'s hosted matrix. It runs the exact `npm ci
  --omit=optional` and `npm run verify` commands on the no-socket Node 22
  worker. Node 20 and 24 and both Windows matrix cells remain in Actions; the
  repository's `main` branch has no protection at this readback and two active
  rulesets, so this supplemental lane is shadow-only.
- `python312-game-signal-garden-v1` maps the credential-free repository
  integrity and release-evidence validators in `game-signal-garden` to the
  pinned Python 3.12.14 worker. It runs the six checked-in Python validator
  commands; Unity/WebGL execution, foreground playtest evidence, and release
  promotion remain explicitly `NOT_RUN` or `NOT_READY` in the Actions workflow.
  The `main` branch has no classic protection or active rulesets at this
  readback, so this supplemental lane is shadow-only.
- `node2214-jira-platform-api-v1` maps only the credential-free `jira-api`
  job in `project-jira-platform`'s monorepo CI. It runs the exact
  `npm --prefix packages/jira-api ci`, `npm --prefix packages/jira-api run
  verify`, and `npm --prefix packages/jira-api run verify:clean-checkout`
  commands on the disposable Node 22.14.0/npm 10.9.2 worker. The Jira Admin,
  contract-fixture, protocol-integration, and required Actions checks remain
  in Actions; the repository's `main` branch is protected with required
  Actions checks, so this supplemental lane is shadow-only.
- `jenkins-repository-contract` runs the centrally defined Node contract suites
  against the current exact PR head of `project-jenkins`: the four portfolio
  profile-contract Node test files and the Test Platform adapter test. Its
  existing private profile is `project-jenkins-self-check`, still shadow-only
  at 0/4. It now uses the no-socket Setness Node/PowerShell worker; the suite
  does not deploy or change Actions authority.
- `setness-web-ci-node22-v1` maps only `project-setness-consulting`'s primary
  Node 22 `ci.yml` job. It runs the fallback-contract PowerShell check, exact-SHA
  fallback runtime check, `npm ci`, typecheck, lint, build, blog validation,
  SEO baseline, and unit tests using fixed commands on a dedicated Node 22.23.3
  plus PowerShell 7.6.6 one-build agent. That agent has no Docker socket or host
  mounts. Cloudflare Candidate, Tutor Web Node 24, scheduled E2E, and deployment
  remain Actions lanes; Actions `build-test` remains authoritative. The private
  profile stays at 0/4 while its exact-head success, visible failure,
  stale-head, and cleanup/recovery cases are collected. Same-repository PRs
  authored by `setnessconsulting` only are eligible; forks and outside authors
  remain rejected.

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
The routine poller allowlist is restricted in trusted code to twenty-five exact
implementation/repository pairs: `project-test-platform`,
`project-game-platform-sdk`, `Game-Planetary-Survey`, `curiouspathway`,
`game-math-detective`, `game-motion-lab`, `game-ecosystem-rescue`, `game-fraction-match`, `project-portfolio-graph`,
`project-vercel-api`, `project-unity-api`, `project-jenkins`,
`project-setness-consulting`, `project-github-api`, `project-investment-council`,
`project-supabase-api`, `project-rive-api`, `game-signal-garden`, `project-jira-platform`, `project-jira-api`, `project-blender-api`,
`project-jira-admin`,
`project-cloudflare-api`, `project-fmod-api`, and `project-game-maker`. The
Jira API pair uses the centrally fixed Node 22.14 clean-checkout commands; its
Actions verification check and manual token-backed fallback remain unchanged.
The Python 3.12 first-wave lanes remain partial shadows: Blender's Python 3.11
matrix leg, Windows, recovery, secret-scan, and lock jobs remain in Actions;
Cloudflare API's push, local, shadow, scheduled, release, and manual fallback
workflows remain in Actions; FMOD retains its Actions Python 3.11 matrix leg,
push trigger, and manual dispatch. Game Maker's central fixed plan includes
both Python 3.11.17 and 3.12.14, but its floating Actions 3.11 patch is not
runtime-identical and its push trigger remains in Actions. Cloudflare API
`verify` remains its required Actions check. These pairs do not change any
profile's shadow status or qualification count. The Jenkins repository pair
uses the already approved `jenkins-repository-contract` implementation; the
poller's same-repository, non-draft, owner-only and exact-live-head checks remain
unchanged. It checks only open, same-repository, non-draft PRs authored by
`setnessconsulting`, queues one exact-head SHA at a time, and persists dispatch
state in Jenkins home. It does not schedule main-branch, fork, or outside-author
verification. The reaper schedule remains maintenance-only. Enabling this
poller does not make a repository Jenkins-authoritative; Actions, protection,
and deployment settings remain unchanged until separately qualified and
approved.

Other centrally implemented shadow profiles remain outside routine polling
when that would broaden their current workflow behavior: Game AI Playtest Lab
fetches a pinned external GameWorld revision, while Context File Maker and CPA
AI Pack have path filters (and Context File Maker has a separate actor-specific
Windows lane). Those profiles remain available for controlled manual checks.

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
