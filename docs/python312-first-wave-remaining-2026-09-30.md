# Python 3.12 first-wave shadow profiles — 2026-09-30

This change adds centrally trusted, manually dispatched Python 3.12.14
verification profiles for the five first-wave repositories that were not yet
represented in the profile catalog: `project-blender-api`, `project-fmod-api`,
`project-game-maker`, `project-context-file-maker`, and `project-cpa-ai-pack`.
The profiles use the existing one-build `setness-python312-ephemeral` agent and
the established `jenkins-pr-gate` check contract. Runtime selection and every
command argument vector live in the public, centrally maintained resolver;
the private catalog stores only implementation IDs and repository metadata.

These are partial shadow lanes, not full workflow replacements. The current
Actions workflows remain authoritative. All five profiles start at 0 of 10
qualification cases, none is added to automatic routine dispatch, fork builds
remain disabled, and no branch protection or repository workflow is changed.

## `project-blender-api`

- Workflow `.github/workflows/ci.yml`, blob
  `92539a770a80ab59d4b35c8cbd6584cdb01557fc`, runs `pure-python`,
  `recovery-safety`, `windows-pure-python`, and `secrets` for pull requests and
  pushes.
- Workflow `.github/workflows/python-lock.yml`, blob
  `0c2d55c2b4cb7059fadee10600d2f72e799af3bc`, runs the four Python 3.11/3.12
  Linux/Windows lock checks only for dependency and lock-related paths.
- Implementation `python312-blender-api-v1` covers the Linux Python 3.12.14
  dependency lock, editable installation, Ruff, mypy, full pytest suite, and
  the separate recovery-safety test selection.
- Residual Actions coverage: Python 3.11, Windows Python 3.12 and its wrapper
  casing/source-binding smoke, Gitleaks, and the path-filtered four-way lock
  matrix. Jenkins does not claim those results.

## `project-fmod-api`

- Workflow `.github/workflows/ci.yml`, blob
  `58d616283283c6f2114d03996e0e7691ba00585d`, runs `pure-python` for pull
  requests, pushes to `main`/`feat/**`/`fix/**`, and manual dispatch. Its
  matrix covers Python 3.11 and 3.12.
- Implementation `python312-fmod-api-v1` covers the Python 3.12.14 lane:
  development install, generated scripting registry drift check, Ruff, the
  repository secret scanner, mypy, pytest, and package build.
- Residual Actions coverage: the Python 3.11 matrix leg and push/manual event
  behavior. Jenkins shadow runs are manually selected against same-repository
  PR heads only.

## `project-game-maker`

- Workflow `.github/workflows/ci.yml`, blob
  `754b88940b4744ea781a0c670c0b5e772a000e06`, runs for pull requests and pushes
  and tests Python 3.11 and 3.12.
- Implementation `python312-game-maker-v1` covers the Python 3.12.14 lane:
  development install, Ruff, mypy, pytest, offline `--version`, `--help`,
  `doctor`, and `status` smoke commands, followed by a clean-working-tree
  assertion.
- Residual Actions coverage: Python 3.11 and push event behavior. The pip
  upgrade command intentionally mirrors the current workflow and is not a
  fixed pip-version pin.

## `project-context-file-maker`

- Workflow `.github/workflows/quality.yml`, blob
  `4b4bd89242e227935e448e875559154803a95145`, runs pull requests, pushes to
  `main`/`master`, and manual dispatch while excluding Markdown and `docs/**`
  paths. It contains hosted Python 3.11 verification and a separate local lane
  enabled only for the Andrewsetness repository/actor condition.
- Implementation `python312-context-file-maker-v1` adds Python 3.12.14
  verification with pytest, `jsonschema`, the full pytest suite, and strict
  schema/template/example validation.
- Residual Actions coverage: the existing Python 3.11 lane, path filters,
  manual `force_hosted` behavior, and the separately conditioned self-hosted
  lane. This is supplemental Python 3.12 coverage, not a claim of parity.

## `project-cpa-ai-pack`

- Workflow `.github/workflows/ci.yml`, blob
  `3477fcc7b89479063e50521a91599aae4f59d3c5`, runs pull requests and pushes to
  `master`/`main` while excluding Markdown and `docs/**` paths. It currently
  installs pytest on Python 3.11, validates the release package, runs pytest,
  and checks the frozen ZIP and release-manifest hashes.
- Implementation `python312-cpa-ai-pack-v1` adds Python 3.12.14 coverage with
  the same release validation, tests, and centrally fixed expected ZIP and
  manifest hashes.
- Residual Actions coverage: the existing Python 3.11 lane and path filters.
  Jenkins does not publish or modify release artifacts.

## Qualification and rollout boundary

The workflow blob IDs above come from the refreshed portfolio inventory; fetch
and compare current source before any later authority change. The manual
portfolio gate still verifies repository ownership, PR state, author policy,
and the exact head before checkout. This change does not enable the poller,
expand the author allowlist, alter Actions triggers, or update GitHub
protection. A cutover decision still needs full workflow parity (including the
residual items above), same-SHA Actions fallback and recovery evidence, the
required exact-SHA qualification record, and protection readback.
