# CI instructions for AI-assisted changes

> Copy and complete this file as the repository's `AGENTS.md` during Jenkins onboarding for Codex/OpenCode. Create a matching Cursor rule in `.cursor/rules/jenkins-ci-authority.mdc` using the repository-specific facts below. Replace every bracketed value using verified repository configuration. Do not treat this template as evidence that Jenkins is live.

## Current CI authority

- Repository: `[owner/repository]`
- Adoption state: `[not onboarded | shadow | qualified but not cut over | Jenkins authoritative]`
- Authoritative PR check(s): `[verified check names and source]`
- Jenkins PR check(s), if enabled: `[exact names and GitHub App attribution, or none]`
- Jenkins-supported triggers/lanes: `[PR, main push, scheduled, manual, by lane]`
- Owner-controlled Actions fallback: `[documented path or not yet qualified]`
- Fork PR support: `[not qualified | qualified, with evidence location]`
- Fork opt-in label: `[jenkins-verify, maintainer-only | not enabled]`
- Deployment boundary: `[manual workflow and provider; state explicitly whether Jenkins can deploy (default: no)]`

## Instructions

- Before making or reviewing a PR, refresh its current head SHA, required checks, and branch-protection state. Report which system is authoritative for this repository.
- If adoption state is `not onboarded` or `shadow`, preserve the current authoritative CI and treat Jenkins only as supplemental shadow evidence. A green Jenkins result does not make the PR mergeable when another check is required.
- If Jenkins is authoritative, verify the configured Jenkins gate is complete on the exact current PR head SHA and is attributed to the expected GitHub App. Do not rely on stale results, another SHA, or local/static tests as hosted Jenkins evidence.
- Do not launch normal GitHub Actions verification after cutover. Use only the documented owner-controlled fallback when appropriate; state which SHA it tested and why it was invoked.
- Never execute a PR-supplied Jenkinsfile or pass the Jenkins GitHub App private key, Checks-write credential, production/deploy credential, controller data, host Docker socket, or persistent agent state to PR-controlled code.
- Fork PRs may run only after this repository's untrusted sandbox, minimal read-only source access, exact-SHA reporting, check publication, and cleanup have been qualified, and a maintainer has applied the documented opt-in label. No label means no passing Jenkins result. Do not permanently deny outside authors by identity, but do not bypass protection or claim fork support before qualification.
- Keep verification separate from release/deployment. Do not deploy or alter deployment triggers, secrets, or protections unless the repository owner separately authorizes that change.
- In PR review summaries, state the exact head SHA, authoritative result, Jenkins check/source and status when applicable, Actions fallback/residual work, and any unresolved verification limitation.

## Cursor rule reminder

The Cursor rule must preserve the same facts as this file and be repository-specific. Use [the Cursor MDC template](cursor-rule.template.mdc), fill in the current verified values, and save it as `.cursor/rules/jenkins-ci-authority.mdc`. Do not add a shared rule that claims Jenkins is required for every repository.
