# Jenkins for Setness Consulting

This repository contains a centrally trusted Jenkins CI system for Setness Consulting repositories. The primary rollout goal is to move verification work onto Jenkins without weakening pull-request gates, secrets handling, or deployment controls. GitHub Actions minutes and billing are secondary context, not the measure of rollout success.

The rollout is staged per repository. GitHub Actions remains each repository's authority until Jenkins passes that repository's exact-SHA, isolation, recovery, fallback, and check-source gates. Track Jenkins-owned verification runs and workflow coverage as the primary progress measures; keep Actions usage/billing as a secondary report.

The current runtime target is a fresh Ubuntu Server VM on Hyper-V. See [the adversarial pilot and decision plan](docs/jenkins-pilot-plan.md) and the [Hyper-V VM shadow-pilot runbook](docs/hyperv-vm-shadow-pilot.md). The prior Docker Desktop checkout and volume are retained locally for rollback; the Hyper-V branch deliberately removes their launch and credential-enrollment scripts.

The first repository profile covers standard Node 22 CI, applicable Cloudflare Candidate checks, applicable Node 24 Tutor Web CI, and a separate manual Playwright E2E job. The optional second-repository profile defaults off and uses a separate read-only checkout credential, explicit trusted-author allowlist, Node 24, and a prebuilt three-browser Playwright image. Its owner-configured smoke URL is optional: until provided, Jenkins reports “not configured” with a neutral check and makes no live request. These are implementation definitions, not qualification evidence. Per-repository Actions workflows remain authoritative until that repository passes its own qualification and cutover gates. See [the repository onboarding profile](docs/secondary-repository-profile.md).

This repository is public; do not put credentials, tokens, private repository identifiers, private build output, or environment-specific secret values here.
