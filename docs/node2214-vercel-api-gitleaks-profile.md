# Vercel API Node 22.14 and Gitleaks shadow profile

The centrally trusted implementation `node2214-vercel-api-gitleaks-v1`
combines the current `project-vercel-api` workflow's `secret-scan` and `test`
jobs under the existing `jenkins-pr-gate` check contract.

The profile uses a separate one-use Node 22.14 disposable agent
(`setness-node22-14-disposable-ephemeral`) with Node.js 22.14.0 and npm 10.9.2.
Its image has no Docker CLI, Docker socket, or host mounts. It stays on the
existing `setness-jenkins-private` network with a one-agent cap, 4 CPU limit,
4 GiB memory limit, and 4 GiB swap limit. Gitleaks 8.24.3 is installed from its
official Linux x64 release archive after SHA-256 verification against the
published release checksums file:
`9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c`. The Node
archive hash `69b09dba5c8dcb05c4e4273a4340db1005abeafe3927efda2bc5b249e80437ec`
matches Node's signed v22.14.0 release checksums. The Gitleaks binary at
`/usr/local/bin/gitleaks` remains root-owned; the Node runtime tree under
`/opt/setness-jenkins/tools/node-v22.14.0-linux-x64` is owned by `jenkins`.
PR commands run as the unprivileged `jenkins` user.

The trusted command vectors run the redacted SARIF-producing `gitleaks dir`
scan first, then `npm ci --ignore-scripts`, `npm run check`, `npm test`, and
`npm run verify`. These are the commands from the live default-branch workflow
at blob `87aee76d58dfa5761195a1218e7771a5fc0742db`. The profile combines two
Actions jobs into one Jenkins result; Actions retains its parallel job shape.

This is a partial exact-head PR shadow. Jenkins does not replace the workflow's
push or owner-dispatched exact-SHA fallback, and it does not cover outside
contributors. The repository's existing Actions workflow remains authoritative
for every trigger. Fork builds remain disabled, the author allowlist is
unchanged, and the centrally trusted resolver rejects non-owner, fork, stale,
and mismatched-base PRs before checkout.

The prior six exact-SHA observations were run through the older Node 22.14 image
with Docker socket access. They remain historical evidence for that worker
class and do not qualify this disposable no-socket image. The private catalog
resets qualification to 0/6 while the new worker is qualified. Exact-head
success/failure, stale-head rejection, cancellation and cleanup, recovery,
controller-published attribution, and the owner-controlled Actions fallback
must be re-established for this worker class. Actions remains authoritative.
