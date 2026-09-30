# Python 3.12 profile mapping: project-test-platform

Status: central implementation ready for shadow use; GitHub Actions `verify`
remains the current workflow. The live `main` branch has no classic protection
and no repository rulesets, so no status check is required by branch policy.
This mapping does not qualify the profile or change branch protection.

## Source workflow

Repository: `setnessconsulting/project-test-platform`

Default branch: `main`

Workflow: `.github/workflows/verify.yml`
Workflow blob at refresh: `5e13e886f100cae38d369614d4ef0313c9b36c22`

The workflow has one `verify` job for pull requests, pushes to `main`, and
manual dispatch. It sets up Python `3.12`, installs the development extra, and
runs the public core verifier. There are no additional jobs or path filters in
this workflow.

## Central implementation

- Implementation ID: `python312-test-platform-v1`
- Check contract: `jenkins-pr-gate`
- Agent label: `setness-python312-ephemeral`
- Python runtime: `3.12.14`, built from the official source archive with its
  SHA-256 pinned in `agent/Python312.Dockerfile`
- Command vector:
  1. `python -m pip install -e ".[dev]"`
  2. `python -m test_platform.verify`

The catalog can select only this implementation ID. Commands, image, label,
and environment are defined centrally. The agent is unprivileged and removed
after one build; checkout credentials are removed before either command runs.

## Qualification and cutover

The 10 exact-SHA cases remain outstanding until recorded against the live
Jenkins check source and the current PR head. Preserve the Actions workflow and
its triggers. Do not designate Jenkins as a required check until complete
qualification, fallback and recovery evidence is recorded and GitHub protection
is read back after an owner-approved policy change.
