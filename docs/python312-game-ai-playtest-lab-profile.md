# Python 3.12 Game AI Playtest Lab profile

`python312-playtest-lab-v1` is the centrally trusted implementation for the
`game-ai-playtest-lab` verification workflow. The private profile may select
this implementation and pin Python `3.12.14`; it cannot provide commands,
scripts, repository URLs, revisions, or agent labels.

The implementation uses the one-build `setness-python312-ephemeral` agent and
the established `jenkins-pr-gate` check. Its fixed command vectors mirror the
workflow's test path:

1. Upgrade pip, then install the repository's `[test]` extra.
2. Clone the public GameWorld repository and check out the workflow's pinned
   revision `3c26bdab436800fd61ef40543b64ca40d12c7e4a`.
3. Run `python -m unittest discover -s tests -p "test_*.py" -v`.

The Actions workflow's PR, `main`/`codex/**` push, and manual triggers have no
path filters. This Jenkins profile is manually dispatched against a live,
same-repository PR head only. Actions retains push and manual coverage and
remains authoritative during shadow qualification. The profile is not added to
the automatic poller. Releases, deployments, and fork builds are outside this
implementation.
