# Portfolio profile contract

The private profile catalog is input data, not a pipeline language. A profile
can select only a centrally implemented ID. It cannot
provide shell text, a Jenkinsfile, an agent label, credentials, environment
variables, network policy, or check conclusions.

`integration/portfolio-profile-contract` defines the strict catalog envelope,
the central implementation registry, exact-SHA request resolution, and the
initial same-repository/owner-only PR policy. Its Node 22 adapter is a
contract-tested component. The manual-only
`portfolio-dispatch/portfolio-pr-gate` invokes it from the controller after
reading the private catalog and refreshing the live PR.
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

There is no portfolio polling or automatic PR verification trigger in this
increment; the reaper schedule is maintenance only.

Fork PRs are rejected. An owner allowlist is a bounded shadow policy, not a
sandbox. Do not broaden access or make this check required until the runtime
consumer verifies repository identity and PR-head SHA through GitHub, publishes
Checks from the controller, and proves agent isolation and cleanup.
