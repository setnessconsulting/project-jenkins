# Vercel API Node 22.14 and Gitleaks shadow profile

The centrally trusted implementation `node2214-vercel-api-gitleaks-v1`
combines the current `project-vercel-api` workflow's `secret-scan` and `test`
jobs under the existing `jenkins-pr-gate` check contract.

The profile pins Node.js 22.14.0 and npm 10.9.2. Its one-use Node 22.14 agent
contains Gitleaks 8.24.3 from the official Linux x64 release archive, verified
against its published SHA-256 checksum
`9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c` during
image construction. The binary is root-owned and the PR build runs as the
unprivileged `jenkins` user.

The trusted command vectors run the redacted SARIF-producing `gitleaks dir`
scan first, then `npm ci --ignore-scripts`, `npm run check`, `npm test`, and
`npm run verify`. These are the commands from the live default-branch workflow
at blob `622e316f4c2d50c7a912c05a83cee17f9742df63`. The profile combines two
Actions jobs into one Jenkins result; Actions retains its parallel job shape.

This is a partial, manual PR shadow. Jenkins does not reproduce the workflow's
push or manual-dispatch triggers, and it does not cover outside contributors.
The repository's existing Actions workflow remains authoritative for every
trigger. Fork builds remain disabled, the author allowlist is unchanged, and
the poller does not include this implementation.

The fixed ten-observation quota is waived. The live catalog records six
distinct exact-SHA outcomes for this profile: exact-head success, stale-head
rejection, visible command failure, recovery success, cancellation, and
published cancellation/cleanup. The duplicate third H3 run is excluded.
Qualification remains incomplete until the owner-controlled Actions fallback
is exercised on a real exact-SHA PR, Jenkins isolation and recovery evidence is
read back from the live controller, and the owner-approved GitHub protection
readback is recorded. Actions remains authoritative until then.
