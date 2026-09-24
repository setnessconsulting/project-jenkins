# Hyper-V Jenkins VM shadow pilot

This runbook creates a new Jenkins installation for shadow testing. The existing Docker Desktop Jenkins volume remains untouched as a rollback copy. The new controller starts with a fresh home; it does not import the old Jenkins volume.

GitHub Actions remains the authoritative merge gate throughout this runbook. Do not change branch protection, target Actions workflows, automatic Vercel behavior, or run a deployment here.

## Stop conditions

- Do not create the VM or move credentials until elevated preflight confirms Hyper-V is enabled, the VM storage volume is fully encrypted and actively protected by BitLocker, and a recovery-password protector exists. Independently confirm that the recovery key is retrievable from its approved backup; the script cannot verify escrow.
- If Hyper-V is unavailable, disk protection is not fully active, the proposed isolated network overlaps an existing host network, or the VM cannot recover after restart, stop. Do not substitute Docker Desktop or WSL2.
- The Docker socket is mounted only into the Jenkins controller inside this VM. Docker daemon access is effectively host-root, so the VM is the security boundary. Build agents never receive the socket.
- Keep the current Docker Desktop volume and the existing Windows DPAPI recovery material. Do not use `docker compose down -v`.
- Keep the repo-scoped read-only SSH deploy key separate from the GitHub App. The App credential is for controller-side discovery and Checks publication; the key is used only by the Branch Source SSH checkout trait. Do not widen builds to other authors or forks during initial qualification.

## Host preflight and VM creation

1. Download an Ubuntu Server 24.04 amd64 ISO from [Canonical's official download page](https://ubuntu.com/download/server). Verify the file against Canonical's published SHA-256 checksum (and signature) from the matching release directory before using it.
2. Open an elevated Administrator PowerShell and run:

   ```powershell
   .\scripts\hyperv-preflight.ps1
   ```

   This is read-only. It must confirm Hyper-V, the VM management service, full BitLocker protection and a recovery-password protector on the chosen storage volume, at least 8 logical CPUs, 32 GiB host memory, and 140 GiB free space. A failure is a stop, not a request to enable features or move data. Separately confirm the recovery key is retrievable from its approved backup without displaying it in logs or chat.
3. Only after that passes, create the VM, providing the independently verified ISO hash:

   ```powershell
   .\scripts\new-jenkins-vm.ps1 `
     -UbuntuServerIsoPath 'C:\path\to\ubuntu-24.04-live-server-amd64.iso' `
     -UbuntuIsoSha256 '<verified-64-character-SHA256>' `
     -RecoveryKeyConfirmation 'RECOVERY-KEY-VERIFIED'
   ```

   The confirmation argument is an explicit operator attestation that the BitLocker recovery key is retrievable from its approved backup. The script creates a Generation 2 VM with Secure Boot, 8 vCPU, 16 GiB fixed RAM, and a 120 GiB dynamically expanding disk under `C:\ProgramData\SetnessConsulting\JenkinsVM`. It also creates an internal Hyper-V switch and outbound NAT for `192.168.218.0/24`. It fails rather than reusing existing VM, switch, NAT, disk, or overlapping route state.
4. In VMConnect, install Ubuntu Server 24.04 with a static address `192.168.218.2/24`, gateway `192.168.218.1`, and DNS `1.1.1.1`. Install OpenSSH only if needed for administration; do not forward SSH to the LAN. Use a unique guest admin password.
5. Configure the guest firewall to deny inbound by default and allow Jenkins TCP `18080` only from `192.168.218.1`. Allow outbound traffic for Ubuntu updates, Docker image pulls, GitHub, and npm. Docker-published ports can bypass UFW rules, so the host-only VM network and the guest's single host-only NIC are also part of the access boundary. Do not add an external Hyper-V switch or a Docker TCP API listener.
6. Install Docker Engine and Compose from [Docker's official Ubuntu instructions](https://docs.docker.com/engine/install/ubuntu/). Do not expose the Docker API over TCP. Enable the Docker service at boot. Verify the daemon uses the local Unix socket and does not listen on `2375` or `2376`.

The VM script sets automatic startup and clean guest shutdown for Windows restarts. The local forward is a separate step, configured only after Jenkins is running on the guest-only address.

## Fresh Jenkins bootstrap

1. Clone this repository inside the guest at `/opt/setnessconsulting/project-jenkins` after the implementation PR is reviewed and merged. Create an ignored `.env` from `.env.example`, set `JENKINS_HTTP_BIND_IP=192.168.218.2`, and fill in the private target's owner/repository, App ID and credential ID, job name, marker, and Candidate path rules. Keep `.env` mode `0600`; never commit it or copy its private values into public docs.
2. Initialize the guest-local administrator secret, then build and start a fresh controller:

   ```bash
   sudo bash scripts/vm/start-jenkins.sh init-secrets
   sudo bash scripts/vm/start-jenkins.sh install
   ```

   The generated password is stored root-only at `/etc/setness-jenkins/secrets/admin-password` on the BitLocker-protected VM disk. Read it only from the VM console when the Windows-side credential provisioning script prompts. The script creates a new Docker named volume `setness-jenkins-vm-home`; it does not reference the old Docker Desktop volume.
3. Verify the JCasC page and Jenkins system information show zero controller executors, one Docker cloud with a one-container cap, and only the intended `setness-ephemeral` label. Confirm that only the controller has `/var/run/docker.sock` mounted. The agent image has no credential or persistent workspace mount.
4. Install and enable the guest service so controller recovery is automatic after a VM or Windows restart:

   ```bash
   sudo install -o root -g root -m 0644 deploy/systemd/setness-jenkins.service /etc/systemd/system/setness-jenkins.service
   sudo systemctl daemon-reload
   sudo systemctl enable setness-jenkins.service
   sudo systemctl start setness-jenkins.service
   sudo systemctl --no-pager status setness-jenkins.service
   ```

   Confirm the VM is configured to start automatically, then perform a controlled guest restart and a Windows restart before qualifying recovery. The Windows portproxy persists, and IP Helper must be running for it to work.
5. Stop the old Docker Desktop controller from the preserved pre-VM checkout using its matching `stop` action. This stops services but preserves its named volume and Windows DPAPI files. Do not remove that checkout or volume.
6. In elevated PowerShell, configure the loopback-only Windows forward:

   ```powershell
   .\scripts\configure-jenkins-vm-forward.ps1
   ```

   The script creates only `127.0.0.1:18080 -> 192.168.218.2:18080`; it refuses to replace a different mapping or take a port already in use. Jenkins remains unreachable from the LAN and internet.
7. After the VM and protected loopback forward are verified, provision the repo-scoped App and the separate read-only checkout key to the new controller. Pass the path to the preserved ignored `.env` if it is not in this checkout:

   ```powershell
   .\scripts\provision-vm-github-app.ps1 -ConfigPath 'C:\path\to\preserved\project-jenkins\.env'
   ```

   Enter the VM bootstrap administrator password at the secure prompt. The script reads the existing DPAPI-protected App key and read-only checkout key, sends them only to loopback, stores them as separate Jenkins credentials, and verifies App repository access. Branch Source's untrusted-context permission restriction does not constrain trusted contexts such as repository indexing, and the Checks publisher uses the App credential in a trusted controller context. Therefore the App must not be used for agent checkout: `SSHCheckoutTrait` uses the separate repository-scoped read-only deploy key. Verify the agent has no copy of that key after checkout and before any pipeline shell step, and confirm the published check is attributed to the App.
8. Recheck that Jenkins returns through `http://127.0.0.1:18080/` after restarts and that the Docker cloud can reconnect.

## Pinned Jenkins and plugin security review

The checked-in pins were reviewed against Jenkins advisories and the Docker plugin compatibility information on 2026-09-23. The controller is pinned to Jenkins LTS `2.568.3`; the Docker plugin pin `1327.v9524f1ee134e` requires Jenkins `2.504.3` or newer. The controller pin is therefore above that plugin minimum and includes the core fixes listed for LTS `2.568.3` in the [2026-09-02 Jenkins advisory](https://www.jenkins.io/security/advisory/2026-09-02/).

The pinned `github-branch-source`, `git-client`, `pipeline-multibranch`, `pipeline-groovy-lib`, and `script-security` versions meet or exceed the respective fixes listed in the [2026-06-24](https://www.jenkins.io/security/advisory/2026-06-24/) and [2026-09-16](https://www.jenkins.io/security/advisory/2026-09-16/) plugin advisories. The Docker plugin's published [compatibility and security information](https://plugins.jenkins.io/docker-plugin/) was also checked. This is a point-in-time review, not an ongoing guarantee: repeat it before rebuilding the controller and again before any cutover. Keep plugin installation pinned; do not use floating `latest` versions.

## Runtime contract

- The checked-in centrally trusted Pipeline runs owner-only same-repository PRs during this bounded shadow. It reads `SCMRevisionAction` on the controller and verifies the Branch Source `PullRequestSCMRevision.getPullHash()` before publishing any PR check or allocating a container. Denied PRs receive an explicit failed primary result and a neutral Candidate “blocked/not run” result. If the head SHA cannot be verified or the publisher cannot resolve it, the build fails closed; a missing required check must never be treated as success.
- The inline pipeline's Groovy sandbox is disabled only because the trusted controller-side SHA verification requires access to the Jenkins run's internal SCM revision action. This makes `project-jenkins` pipeline changes privileged controller code: review those changes before import, keep the target Jenkinsfile unused, and never interpolate target-controlled content into Groovy evaluation.
- GitHub Branch Source publishes checks against the PR head SHA. Verify the actual App attribution and exact head SHA on controlled test PRs; do not infer it from a Jenkins build URL.
- Each authorized build gets one unprivileged, resource-limited Docker agent (4 CPU, 8 GiB memory, no additional swap), one executor, and no persistent workspace/cache, host mounts, controller state, Docker socket, or production secret. The controller-side GitHub App is never used for checkout. The separate repository-scoped read-only SSH key is used only by the SCM checkout operation; prove it is absent from the agent before any repository-controlled command runs. Docker once-retention is configured for zero idle minutes; the Pipeline also deletes its workspace in `finally`. Verify actual container removal after success, failure, and cancellation before accepting this boundary.
- Standard Node 22 checks and the relevant Cloudflare Candidate checks share one checkout and one `npm ci`. Candidate is neutral/not-applicable for changes outside configured paths; classification errors fail the primary gate closed.
- Direct fork PRs are excluded. Do not broaden the author allowlist until the disposable boundary, exact-SHA reporting, cleanup, denial reporting, and recovery have all passed.

## Shadow qualification and cutover boundary

This VM only enables testing; it does not qualify Jenkins for cutover. Before Jenkins becomes required, complete all of the following:

- At least 10 distinct exact-head-SHA comparisons spanning source, lockfile, docs-only, Jenkins config, Candidate changes, and deliberate failures. Include stale heads, cancellation, cleanup, denied authors, Candidate not-applicable behavior, and reviewer-visible summaries. Use fresh matching Actions results; do not trigger a billable fallback run without owner approval for that specific run.
- Confirm disposable containers disappear after pass, failure, and cancellation; no agent can access controller state, Docker socket, App key, Checks write token, or production credentials.
- Prove Windows/VM restart and reconnection, backup and restore of fresh Jenkins home plus encryption material, and owner-controlled same-SHA Actions fallback. A full backup includes `secrets/master.key` and `secrets/hudson.util.Secret`; keep it only on encrypted storage unless separately encrypted before transfer.
- Capture a complete Actions billing period, billable hosted minutes and total workflow minutes by workflow/runner type, and remaining effort for self-hosted Actions. Keep deploy runs separate from CI savings; retain scheduled/manual E2E and Tutor Web workflows on Actions.
- Keep branch protections and Actions unchanged until the GO review. Only then use the documented dual-gate transition and read back the enforced ruleset before removing any existing requirement.

If a gate fails, keep Actions authoritative and Jenkins shadow-only.

## Operations and rollback

Inside the VM, use `sudo bash scripts/vm/start-jenkins.sh status|logs|restart|stop`. `stop` preserves the fresh VM volume; never use `down -v`.

For a consistent local backup, wait until no build container remains, stop Jenkins, then run:

```bash
sudo bash scripts/vm/backup-jenkins.sh
```

The script refuses to run while the controller or one-use agent is active. It archives the complete Jenkins home (including `secrets/master.key` and `secrets/hudson.util.Secret`), the root-only bootstrap secret, the ignored mode-0600 runtime `.env`, and the exact checked-in configuration commit. It writes checksums and keeps the bundle under `/var/backups/setness-jenkins` on the encrypted VM disk. This is a restore rehearsal copy, not protection from loss of the PC or VM disk; encrypt separately before transferring it elsewhere.

To rehearse restoration without touching the active Jenkins home, use the exact directory printed by the backup command:

```bash
sudo bash scripts/vm/restore-jenkins-backup.sh /var/backups/setness-jenkins/jenkins-<timestamp>
```

The drill verifies checksums and the recorded repository commit, extracts into a new named volume, then starts Jenkins on Docker's `none` network with no Docker socket or host port. The temporary container is removed after its ready marker is observed; the restore volume and root-only recovered config/secrets remain for inspection. A failure preserves those restore artifacts for diagnosis and never overwrites the active volume.

For rollback, stop Jenkins in the VM, remove only the exact loopback portproxy with `scripts/rollback-jenkins-vm-forward.ps1`, then start the preserved pre-VM Docker Desktop checkout. The script restores IP Helper's recorded startup mode only when no other portproxy mappings remain and the service mode has not been independently changed; it does not stop IP Helper. Do not delete the VM, its volume, or the old Jenkins volume as part of rollback. No branch protection or target Actions setting is changed by this pilot branch.
