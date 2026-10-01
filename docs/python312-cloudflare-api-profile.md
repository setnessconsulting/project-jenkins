# Python 3.12 Cloudflare API shadow profile

`python312-cloudflare-api-uv-v1` maps only the pull-request verification job in
`project-cloudflare-api`'s main workflow. It is a partial workflow mapping, not
full-repository qualification or a cutover.

## Source and command map

- Repository default branch: `main`
- Observed repository head: `174e9b57720fe4ed824c0bc3cfb9dcc9bf546eae`
- Workflow: `.github/workflows/ci.yml`
- Workflow blob: `6d70aa59f3b7167b33d183e350d9f2c9a31e37b1`
- Workflow ID and job: `354186851`, `verify` on `ubuntu-24.04`
- Events: pull request and push; no path filter
- Python pin: `3.12.14`
- uv pin: `0.11.17`
- Jenkins profile: `project-cloudflare-api-python312-uv`
- Centrally trusted implementation: `python312-cloudflare-api-uv-v1`
- Jenkins check contract: `jenkins-pr-gate`

The static commands install the pinned uv release, synchronize the locked dev
environment, run `scripts/verify.py`, and run `cloudflare-api doctor --json`.
The profile cannot supply executable fields or change these commands.

## Current authority and remaining workflows

At this readback, the `.github/workflows/ci.yml` push check `verify` passed on
the observed main SHA from the GitHub Actions App (ID `15368`, run
`36210865988`, job `108316906487`). GitHub protection requires the Actions
`verify` context from App `15368`; the active ruleset is
`setness-main-protection`. No Jenkins requirement or protection setting was
changed. Actions remains authoritative. No open pull request was available for
exact-SHA shadow runs, so its behavior matrix remains incomplete.

The repository also has `ci-local.yml`, `ci-shadow.yml`, and
`ci-hosted-fallback.yml`. Their reusable self-hosted lanes, release event,
weekly schedule, and manual lane selection remain in Actions and are not
covered by this profile. No release, deployment, or scheduled workflow was
moved. The automatic Jenkins poller and fork builds remain disabled. The
same-SHA Actions fallback has not been exercised for this profile.

Before promotion, map or explicitly retain every residual verification path,
complete the exact-SHA qualification cases and fallback/recovery evidence, and
read back owner-approved GitHub protection for this repository.
