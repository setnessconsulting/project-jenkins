# Jenkins for Setness Consulting

This repository evaluates Jenkins as a self-hosted CI/CD option, starting with a private site repository. The goal is to reduce GitHub Actions usage without weakening the pull-request gate, secrets handling, or deployment controls.

The plan is deliberately comparative: the existing self-hosted GitHub Actions runner may achieve the same minute reduction with less migration work. Jenkins should be adopted only if the pilot proves its checks, operational reliability, recovery, fallback, and total effort are better for this use case. GitHub Actions remains authoritative until then.

The current runtime target is a fresh Ubuntu Server VM on Hyper-V. See [the adversarial pilot and decision plan](docs/jenkins-pilot-plan.md) and the [Hyper-V VM shadow-pilot runbook](docs/hyperv-vm-shadow-pilot.md). The prior Docker Desktop checkout and volume are retained locally for rollback; the Hyper-V branch deliberately removes their launch and credential-enrollment scripts.

This repository is public; do not put credentials, tokens, private repository identifiers, private build output, or environment-specific secret values here.
