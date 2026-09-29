# Portfolio profile controller adapter

`integration/portfolio-profile-contract/src/resolve-pr.mjs` is a bounded stdin
adapter for the centrally trusted profile resolver. It accepts one closed JSON
envelope containing the private profile catalog, trusted GitHub PR metadata,
and a request with repository identity, PR number, and exact head SHA. It caps
input at 1 MiB, rejects command-line arguments and caller-supplied author
policy, fixes the initial allowlist to `setnessconsulting`, and returns only a
centrally defined execution plan or a stable rejection code.

The eventual Jenkins caller must assemble the catalog and PR object on the
controller from the private catalog and trusted GitHub data. It must refresh
the PR through GitHub's API immediately before invoking the adapter and compare
the live open PR's head SHA with the Branch Source revision; a scan snapshot
alone can be stale. Never accept the envelope from a target workspace or pass
the catalog or adapter to a build agent. The Dockerfile packages the adapter
only into the controller image; the agent images do not include it.

This is an invocation contract, not live Jenkins integration. No Jenkins job
calls the adapter, no App token is fetched, no GitHub Check is published, and
no repository profile is enabled by this change. A runtime caller still needs
to prove repository-scoped read access, controller-only Checks publication,
disposable-agent cleanup, and exact-SHA behavior before any shadow profile can
be enabled.
