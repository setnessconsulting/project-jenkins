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
- The initial shadow pipeline compares trusted `CHANGE_AUTHOR` metadata against the locally configured repository owner before checkout. Non-owner PRs fail closed and run no target-repository commands. GitHub Branch Source discovery is restricted to origin PRs; do not widen the author allowlist during this pilot.
- Residual risk: Jenkins' inbound-agent secret is available to the agent process, and PR build steps run under the same unprivileged account in that container. Treat arbitrary PR code as able to read/steal that one-agent secret. The repository-scoped read-only SSH key is also used during agent checkout; prove it cannot be recovered from temporary files/process state after checkout or treat it as exposed. Do not run builds from untrusted contributors; recreate/re-enroll the agent and rotate/revoke exposed checkout credentials after suspected compromise. If this boundary is unacceptable, stop before using Jenkins as a merge gate and move to disposable agents with a stronger process boundary.
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
- Shadow runs have demonstrated successful standard and Candidate suites on Candidate-relevant changes, and a real source change has correctly failed the standard typecheck. The Jenkins App attributed its checks to the exact PR head SHA. These are useful function/failure-path samples, not the required 10-case parity matrix.
- The build completed the standard suite and the Candidate suite: MDX validation, `vinext check`, the staging build, Cloudflare config validation, Wrangler validation, and Wrangler deploy dry-run. No production deploy or Cloudflare credential was used.
- A deliberate standard-CI failure produced a failed `jenkins-pr-gate` with the typecheck error in its GitHub summary; `cloudflare-candidate` correctly reported neutral/not-run because standard CI failed first.
- A non-allowlisted same-repository PR was rejected before checkout, and the checkout stage was skipped. It received no passing Jenkins result, but no Jenkins check run was published for the rejected build; treat denial-check visibility as unresolved.
- An earlier run exposed a false-green: Candidate classification failed but the primary gate passed. The state handling is now outside Declarative `environment`, the post action fails the primary gate closed when a relevant Candidate run was skipped, and the pipeline runs behavioral policy assertions before checkout. Keep this regression in the deliberate-failure matrix.
- Plain `.md` files are now excluded from Candidate path classification; `.mdx` remains eligible because it is validated and built. A live docs-only not-applicable check and workspace marker cleanup test are still pending.
- Jenkins did not trigger a GitHub Actions workflow run. Existing Actions workflows remain enabled; this single shadow test is not a measured monthly savings comparison.
- The available Actions Usage Metrics view is only a partial current-month snapshot, so the full-period baseline and effort comparison are still outstanding. Treat Actions runs that fail before starting steps as inconclusive—not as application test failures or parity evidence.
- Jenkins’ configured root URL is intentionally loopback-only, so check-detail links work only in a browser on this same machine. Do not expose the controller to make those links work for remote users. Earlier runs showed an empty primary-check `summary` because the Checks plugin's automatic completion update overwrote the Pipeline summary. Keep automatic primary-check lifecycle publication enabled: suppressing it can leave an older green result in place when a trusted Pipeline fails to parse. The pipeline still attempts a concise explicit summary, and the plugin may replace it with its stage-and-duration text; verify the final rendered output on live PRs before calling shadow usable or considering cutover. Candidate remains an explicit separate result.
- After the configuration-reconciling restart, the controller API read back zero controller executors and the isolated agent online. Checks on current PR heads were attributed to the configured Jenkins App; completed check records linked to the loopback Jenkins URL. Additional checks were still queued or in progress at the readback, so this is not full parity evidence.
- On 2026-09-23, all checked-in GitHub SSH host-key fingerprints matched GitHub's published fingerprints. The pinned Jenkins core and plugin versions were checked against the live Jenkins Update Center security-warning ranges; no pinned version matched an active warning. Repeat this review before every core/plugin update.
- The main-branch rule still requires the existing Actions result, not Jenkins. The owner-selected pilot policy is zero required approvals until an independent reviewer exists, administrator enforcement, and PR-only bypass for two privately designated break-glass identities. Apply/read back that policy only after GO; retain exact identities and branch-policy state in the private decision record.

## Centrally defined pilot job

- `casc/jobs.groovy` reads the target owner, repository, job name, and Candidate path rules from the ignored local `.env`. It injects the locally configured repository owner as the sole PR author allowlist. The checked-in Job DSL and pipeline template contain no private target identifier. It uses a five-minute poll and a central inline Pipeline sourced from `casc/pipelines/repository-pilot.groovy`.
- The marker file is supplied through ignored local configuration. If a PR deletes that marker, Jenkins may not create a branch job; the required check would remain absent and therefore block a later required-check merge, but this edge case must be tested before cutover.
- The primary check name is `jenkins-pr-gate`; the GitHub Checks plugin lifecycle publisher remains enabled so queue, parse, failure, and completion states replace stale results. Cloudflare Candidate path rules are supplied from local config and injected into the trusted inline pipeline. The separate `cloudflare-candidate` check starts in progress after owner authorization, becomes neutral/not-applicable as soon as trusted path classification says it does not apply, and is completed with the final relevant-suite result otherwise. The trusted Pipeline attempts reviewer-readable summaries for both checks, with final primary-check rendering still subject to plugin completion behavior. The primary check conclusion governs the merge; the separate Candidate summary never substitutes for a passing primary gate.
- Plain `.md` documentation changes do not trigger Candidate checks even when they are under a configured directory prefix; `.mdx`, application, and explicitly configured workflow paths remain eligible.
- The agent image pins the official Jenkins inbound-agent base by digest and installs Node.js 22.23.2 only after checking the official Node.js archive SHA-256. The exact Node version is verified in each build.
- The job refers to the repository-scoped GitHub App credential ID `setness-jenkins-app`. The approved permission model is Metadata, Contents read, Pull requests read, and Checks read/write; the Branch Source and Checks plugins share that credential.
- The GitHub App is installed on only the locally configured target repository, with Metadata read, Contents read, Pull requests read, and Checks read/write. Because the Checks plugin reuses the Branch Source credential, that App credential is restricted to Jenkins controller-side discovery and check publication. A separately scoped read-only SSH deploy key is used by the `SSHCheckoutTrait` for source checkout; never set the App credential as the SSH checkout credential.
- The target PR's Jenkinsfile is not used. The central Pipeline runs on the dedicated agent and receives no production or deployment credentials. The Candidate result is tracked separately from the standard gate so a standard-CI failure cannot falsely claim the Candidate suite failed when it did not run.

This remains shadow-only, not a merge gate; cutover readiness is currently blocked. Deploy-key registration, GitHub credential import/readback, controller startup, agent enrollment, polling, check attribution, and initial shadow-build evidence are verified. Before cutover, complete the 10 matched-PR parity matrix (including a mergeable not-applicable PR, deliberate failure, stale head, and cancellation), exercise the same-SHA Actions fallback, rehearse backup/restore, prove Windows restart and agent recovery, confirm reviewers can interpret the combined GitHub Check output, and resolve the persistent agent-secret boundary. Capture a complete Actions usage period and compare remaining Jenkins effort against the existing self-hosted Actions route. At cutover, enforce administrators, keep approvals at zero until an independent reviewer exists, configure only the two private PR-only break-glass identities, and grant the second identity minimum required repository access. Do not change branch protection, pause automatic releases, or disable Actions until all acceptance criteria pass and the comparison supports GO. Never load a Jenkinsfile from the target pull request.
