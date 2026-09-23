# Local Jenkins pilot controller

This provisions a private Jenkins controller, one isolated inbound agent, and the first centrally defined pilot job. The target repository's Jenkinsfile is never loaded. The repository's normal GitHub Actions checks remain authoritative; no production credentials, deployments, or cutover are configured.

The repository is public. Target owner/name, installed App ID, job name, and Candidate path rules belong in the ignored local `.env`, not in committed files. On a fresh clone, copy `.env.example` to `.env` and fill in those non-secret values. Never put passwords, tokens, or private-key contents in `.env`.

## Safety boundary

- The Jenkins UI is published only on `127.0.0.1` (default port `18080`). Do not add a LAN or router binding. The WSL2 NAT route could not reach that host binding, so the selected agent runs as a Docker service on the Compose-private bridge network instead.
- Controller state is stored in a Docker named volume, outside this repository. The repository contains configuration only.
- The built-in controller has zero executors. Jobs are restricted to the single `setness-linux` agent label.
- The inbound agent uses WebSocket to `controller:8080` on the private Compose network; neither the agent port nor controller-to-agent TCP port is published.
- GitHub checkout uses a repository-only, read-only SSH deploy key. GitHub's published SSH host keys are pinned in the agent image's `known_hosts`; do not replace this with trust-on-first-use.
- The agent is one unprivileged Linux executor, separate from the existing Actions runner. It has no host mounts, controller-volume access, Docker socket, Windows profile, existing Actions runner roots, GitHub App credential, or production credential.
- The agent needs outbound access for GitHub checkout and package downloads. A Docker bridge prevents direct host port publication but is not a full VM or outbound firewall. PR build code can reach the controller service on the Compose network.
- Residual risk: Jenkins' inbound-agent secret is available to the agent process, and PR build steps run under the same unprivileged account in that container. Treat arbitrary PR code as able to read/steal that one-agent secret. Do not run builds from untrusted contributors; recreate/re-enroll the agent after suspected compromise. If that residual risk is unacceptable, stop before using this as a merge gate and move to disposable VM agents with a stronger process boundary.
- The local Jenkins account is a bootstrap administrator. Sign-up is disabled and anonymous read is disabled. This single-user authorization setup is not suitable for broader adoption without an explicit access-control review.
- `scripts/start-controller.ps1` generates a random bootstrap password on first use and stores a DPAPI-protected copy under `%LOCALAPPDATA%\SetnessConsulting\JenkinsPilot`, outside the repository. It supplies the value to Compose only for that local process invocation. `scripts/show-admin-password.ps1` reveals it only when explicitly run in a local PowerShell window; do not paste it into chat or commit local state.
- `scripts/enroll-agent.ps1` authenticates to the loopback-only controller using that local DPAPI credential, retrieves the node's one-agent JNLP secret, stores a DPAPI-protected copy outside the repository, starts the agent, and verifies the node is online. Docker's local service metadata necessarily receives the secret at runtime; local Docker administrators can inspect it.
- `scripts/add-readonly-deploy-key.ps1` creates the target repository's read-only deploy key through the GitHub CLI account matching the locally configured owner. Its private key is DPAPI-protected under the local JenkinsPilot state directory; the generated plaintext key file is removed after protection.
- `scripts/provision-github-credentials.ps1` imports the installed GitHub App and the read-only checkout key into Jenkins' encrypted global credential store. The App is restricted to the pilot repository and stays controller-side for discovery and Checks; `SSHCheckoutTrait` selects the separate read-only key for agent checkout. The script converts the downloaded App key to the PKCS#8 format required by Jenkins, retains a DPAPI-protected local recovery copy, and does not print credential contents.
- Docker Compose configures `unless-stopped`, but Windows-login/reboot recovery still requires a real host lifecycle test before the controller is trusted.
- `scripts/start-controller.ps1 restart` rebuilds and force-recreates the configured services while retaining the named Jenkins volume. A plain `docker compose restart` would leave changed Compose environment and service configuration unapplied.

## Start the controller

From PowerShell, first start the controller:

```powershell
.\scripts\add-readonly-deploy-key.ps1
.\scripts\start-controller.ps1 start
```

The deploy-key script is repeatable and verifies GitHub reports the key as read-only. The controller script generates a random password only on first use. Subsequent `start`, `stop`, `restart`, `status`, and `logs` actions reuse the DPAPI-protected local value. To sign in through a browser, run `.\scripts\show-admin-password.ps1` in a local PowerShell window; keep the output local. The container receives the password as an environment variable so JCasC can recreate the local administrator on restart; Docker administrators on this machine can inspect container configuration.

Once the controller responds, provision the two GitHub credentials and enroll the agent:

```powershell
.\scripts\provision-github-credentials.ps1
.\scripts\enroll-agent.ps1
```

The script reports success only after Jenkins says the agent is online. Open `http://127.0.0.1:18080/` to inspect the controller. The node definition alone is not proof that an agent is connected.

## Stop and preserve data

```powershell
.\scripts\start-controller.ps1 stop
```

Do not use `docker compose down -v` for routine stops. Removing the named volume would delete Jenkins state, including credentials and encryption-key material. A backup must include both the complete Jenkins home and separately protected key material; restore must be rehearsed before adoption.

## Current gates

- Jenkins is shadow-only. A live readback on 2026-09-23 confirmed the existing Actions check remains required; Jenkins is not required and Actions remains authoritative.
- The first corrected Candidate-relevant owner PR completed successfully in 455 seconds. The `jenkins-pr-gate` and `cloudflare-candidate` checks from the Jenkins GitHub App both reported success for the exact PR head SHA.
- The build completed the standard suite and the Candidate suite: MDX validation, `vinext check`, the staging build, Cloudflare config validation, Wrangler validation, and Wrangler deploy dry-run. No production deploy or Cloudflare credential was used.
- An earlier run exposed a false-green: Candidate classification failed but the primary gate passed. The state handling is now outside Declarative `environment`, the post action fails the primary gate closed when a relevant Candidate run was skipped, and the pipeline runs behavioral policy assertions before checkout. Keep this regression in the deliberate-failure matrix.
- A docs-only PR could not exercise “not applicable” because GitHub reported a merge conflict and Branch Source could not fetch a synthetic merge revision. No pipeline stages ran and no Jenkins check was published. Repeat that case on a mergeable docs-only PR; do not change PR checkout from merge revision to head merely to bypass mergeability.
- Jenkins did not trigger a GitHub Actions workflow run. Existing Actions workflows remain enabled; this single shadow test is not a measured monthly savings comparison.
- Jenkins’ configured root URL is loopback-only, so check-detail links can work only in a browser on this same machine. Do not expose the controller to make those links work for remote users; a shared-access design is a separate security decision.
- After the configuration-reconciling restart, the controller API read back zero controller executors and the isolated agent online. Checks on current PR heads were attributed to the configured Jenkins App; completed check records linked to the loopback Jenkins URL. Additional checks were still queued or in progress at the readback, so this is not full parity evidence.
- On 2026-09-23, all checked-in GitHub SSH host-key fingerprints matched GitHub's published fingerprints. The pinned Jenkins core and plugin versions were checked against the live Jenkins Update Center security-warning ranges; no pinned version matched an active warning. Repeat this review before every core/plugin update.
- The main-branch rule still requires the existing Actions result, not Jenkins. Required review, administrator-enforcement, and bypass policy must receive explicit owner approval before cutover; retain the exact branch-policy readback in the private decision record, not this public repository.

## Centrally defined pilot job

- `casc/jobs.groovy` reads the target owner, repository, job name, and Candidate path rules from the ignored local `.env`. The checked-in Job DSL and pipeline template contain no private target identifier. It uses a five-minute poll and a central inline Pipeline sourced from `casc/pipelines/repository-pilot.groovy`.
- The marker file is supplied through ignored local configuration. If a PR deletes that marker, Jenkins may not create a branch job; the required check would remain absent and therefore block a later required-check merge, but this edge case must be tested before cutover.
- The primary check name is `jenkins-pr-gate`. Cloudflare Candidate path rules are supplied from local config and injected into the trusted inline pipeline; other PRs receive a neutral `cloudflare-candidate` result saying “not applicable.”
- The agent image pins the official Jenkins inbound-agent base by digest and installs Node.js 22.23.2 only after checking the official Node.js archive SHA-256. The exact Node version is verified in each build.
- The job refers to the repository-scoped GitHub App credential ID `setness-jenkins-app`. The approved permission model is Metadata, Contents read, Pull requests read, and Checks read/write; the Branch Source and Checks plugins share that credential.
- The GitHub App is installed on only the locally configured target repository, with Metadata read, Contents read, Pull requests read, and Checks read/write. Because the Checks plugin reuses the Branch Source credential, that App credential is restricted to Jenkins controller-side discovery and check publication. A separately scoped read-only SSH deploy key is used by the `SSHCheckoutTrait` for source checkout; never set the App credential as the SSH checkout credential.
- The target PR's Jenkinsfile is not used. The central Pipeline runs on the dedicated agent and receives no production or deployment credentials. The Candidate result is tracked separately from the standard gate so a standard-CI failure cannot falsely claim the Candidate suite failed when it did not run.

This remains shadow-only, not a merge gate. Deploy-key registration, GitHub credential import/readback, controller startup, agent enrollment, polling, check attribution, and successful shadow-build evidence are verified. Before cutover, complete the 10 matched-PR parity matrix (including a reachable not-applicable PR, deliberate failure, stale head, and cancellation), backup/restore rehearsal, Windows host restart recovery, shared-access check-link decision, plugin compatibility/security review on update, and an explicit review of the agent's residual secret boundary. Obtain owner approval for the intended review threshold, administrator enforcement, and bypass actors, and keep the exact branch-policy snapshot private. Do not change branch protection or disable Actions until these checks pass and the comparison supports GO. Never load a Jenkinsfile from the target pull request.
