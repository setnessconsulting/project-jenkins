# Jenkins for Setness Consulting

This repository evaluates Jenkins as a self-hosted CI/CD option, starting with the private Setness Consulting site repository. The goal is to reduce GitHub-hosted Actions minutes without weakening the pull-request gate, secrets handling, or deployment controls.

The plan is deliberately comparative: the existing self-hosted GitHub Actions runner may achieve the same minute reduction with less migration work. Jenkins should be adopted only if the first-repository pilot proves its checks, operational reliability, and total effort are better for this use case.

See [the adversarial pilot and decision plan](docs/jenkins-pilot-plan.md). This repository is public; do not put credentials, tokens, private build output, or environment-specific secret values here.
