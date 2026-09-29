import test from 'node:test';
import assert from 'node:assert/strict';
import {
  listRoutinePullRequestPollRepositories,
  planRoutinePullRequestPoll,
} from '../src/consumer.mjs';

const repository = 'setnessconsulting/project-jira-api';
const shaA = 'a'.repeat(40);
const shaB = 'b'.repeat(40);
const now = 2_000_000;
const retryAfterMs = 15 * 60 * 1000;

function makeCatalog({ controlPlaneStatus = 'active', profileStatus = 'shadow', implementationId = 'node22-verify-clean-checkout-v1' } = {}) {
  const qualification = profileStatus === 'qualified'
    ? {
      requiredExactShaCases: 10,
      qualifiedExactShaCases: 10,
      state: 'passed',
      evidenceReference: 'evidence://project-jira-api/sha-matrix',
    }
    : { requiredExactShaCases: 10, qualifiedExactShaCases: 0, state: 'in-progress' };
  return {
    schemaVersion: 1,
    approvedImplementations: [implementationId],
    profiles: [{
      id: 'project-jira-api-profile',
      implementationId,
      status: profileStatus,
      repositories: [repository],
      checkNames: ['jenkins-pr-gate'],
      requiredNodeVersion: '22.14.0',
      qualification,
    }],
    controlPlane: {
      repository: 'setnessconsulting/project-jenkins-config',
      validationProfileId: 'private-catalog-validation',
      status: controlPlaneStatus,
    },
  };
}

function makePullRequest({ number = 7, sha = shaA, author = 'setnessconsulting', headRepository = repository, draft = false } = {}) {
  return {
    number,
    state: 'open',
    draft,
    user: { login: author },
    head: { sha, repo: { full_name: headRepository } },
    base: { repo: { full_name: repository } },
  };
}

function state({ number = 7, sha = shaA, attempt = 1, dispatchedAtEpochMs = now, status = 'pending', dispatchId } = {}) {
  return {
    repository,
    pullRequestNumber: number,
    headSha: sha,
    attempt,
    dispatchedAtEpochMs,
    status,
    ...(dispatchId ? { dispatchId } : {}),
  };
}

function observation({ number = 7, sha = shaA, status = 'in_progress' } = {}) {
  return { repository, pullRequestNumber: number, headSha: sha, status };
}

function plan(catalog, pullRequests, previousState = [], checkObservations = [], nowEpochMs = now) {
  return planRoutinePullRequestPoll(
    catalog, [{ repository, pullRequests }], previousState, checkObservations, nowEpochMs,
  );
}

test('polling is inert until the private control plane is explicitly active', () => {
  const catalog = makeCatalog({ controlPlaneStatus: 'planned' });
  assert.deepEqual(listRoutinePullRequestPollRepositories(catalog), []);
  const previousState = [state()];
  assert.deepEqual(planRoutinePullRequestPoll(catalog, [], previousState, [], now), {
    status: 'inactive', dispatches: [], state: previousState,
  });
});

test('a new same-repository owner PR dispatches only its exact head SHA', () => {
  const result = plan(makeCatalog(), [makePullRequest()]);
  assert.deepEqual(result.dispatches, [{
    repository,
    pullRequestNumber: 7,
    headSha: shaA,
    profileId: 'project-jira-api-profile',
    attempt: 1,
  }]);
  assert.deepEqual(result.state, [state()]);
});

test('multiple eligible PRs queue one at a time and only the selected PR advances state', () => {
  const catalog = makeCatalog();
  const pullRequests = [7, 8, 9, 10].map((number) => makePullRequest({ number }));
  const first = plan(catalog, pullRequests);
  assert.equal(first.dispatches.length, 1);
  assert.equal(first.dispatches[0].pullRequestNumber, 7);
  assert.deepEqual(first.state, [state({ number: 7 })]);

  const afterFirstCompletes = plan(
    catalog,
    pullRequests,
    [state({ number: 7 })],
    [observation({ number: 7, status: 'completed' })],
  );
  assert.equal(afterFirstCompletes.dispatches.length, 1);
  assert.equal(afterFirstCompletes.dispatches[0].pullRequestNumber, 8);
  assert.deepEqual(afterFirstCompletes.state, [
    state({ number: 7, status: 'completed' }),
    state({ number: 8 }),
  ]);
});

test('an in-progress exact-SHA check is not queued again, but a changed SHA starts a fresh attempt', () => {
  const previous = [state()];
  const unchanged = plan(makeCatalog(), [makePullRequest()], previous, [observation()]);
  assert.deepEqual(unchanged.dispatches, []);
  assert.deepEqual(unchanged.state, previous);

  const changed = plan(makeCatalog(), [makePullRequest({ sha: shaB })], previous);
  assert.equal(changed.dispatches.length, 1);
  assert.equal(changed.dispatches[0].headSha, shaB);
  assert.equal(changed.dispatches[0].attempt, 1);
  assert.deepEqual(changed.state, [{ ...state(), headSha: shaB }]);
});

test('a completed App-attributed check is terminal regardless of conclusion', () => {
  const result = plan(makeCatalog(), [makePullRequest()], [state()], [observation({ status: 'completed' })]);
  assert.deepEqual(result.dispatches, []);
  assert.deepEqual(result.state, [{ ...state(), status: 'completed' }]);
});

test('a missing check waits through the grace period before a bounded retry', () => {
  const previous = [state()];
  const beforeGrace = plan(makeCatalog(), [makePullRequest()], previous, [observation({ status: 'missing' })], now + retryAfterMs - 1);
  assert.deepEqual(beforeGrace.dispatches, []);
  assert.deepEqual(beforeGrace.state, previous);

  const retry = plan(makeCatalog(), [makePullRequest()], previous, [observation({ status: 'missing' })], now + retryAfterMs);
  assert.equal(retry.dispatches.length, 1);
  assert.equal(retry.dispatches[0].attempt, 2);
  assert.deepEqual(retry.state, [{ ...state(), attempt: 2, dispatchedAtEpochMs: now + retryAfterMs }]);
});

test('an orphaned in-progress check waits through the grace period before recovery', () => {
  const previous = [state({ dispatchId: '8e8752b3-c0d2-4aaf-8bb2-a19c53c809f9' })];
  const beforeGrace = plan(
    makeCatalog(), [makePullRequest()], previous, [observation({ status: 'orphaned' })], now + retryAfterMs - 1,
  );
  assert.deepEqual(beforeGrace.dispatches, []);
  assert.deepEqual(beforeGrace.state, previous);

  const recovered = plan(
    makeCatalog(), [makePullRequest()], previous, [observation({ status: 'orphaned' })], now + retryAfterMs,
  );
  assert.equal(recovered.dispatches.length, 1);
  assert.equal(recovered.dispatches[0].attempt, 2);
  assert.deepEqual(recovered.state, [{ ...state({ attempt: 2, dispatchedAtEpochMs: now + retryAfterMs }) }]);
});

test('an in-progress check not linked to this poller is never overwritten or retried', () => {
  const previous = [state()];
  const beforeGrace = plan(
    makeCatalog(), [makePullRequest()], previous, [observation({ status: 'untracked' })], now + retryAfterMs - 1,
  );
  assert.deepEqual(beforeGrace.dispatches, []);
  assert.deepEqual(beforeGrace.state, previous);

  const afterGrace = plan(
    makeCatalog(), [makePullRequest()], previous, [observation({ status: 'untracked' })], now + retryAfterMs,
  );
  assert.deepEqual(afterGrace.dispatches, []);
  assert.deepEqual(afterGrace.state, [{ ...state(), status: 'stalled' }]);
});

test('a missing exact-SHA check is stalled after the bounded retry budget', () => {
  const previous = [state({ attempt: 3, dispatchedAtEpochMs: now - retryAfterMs })];
  const result = plan(makeCatalog(), [makePullRequest()], previous, [observation({ status: 'missing' })]);
  assert.deepEqual(result.dispatches, []);
  assert.deepEqual(result.state, [{ ...previous[0], status: 'stalled' }]);
});

test('a late exact-SHA check can reconcile a previously stalled entry', () => {
  const previous = [state({ attempt: 3, status: 'stalled', dispatchedAtEpochMs: now - retryAfterMs })];
  const result = plan(makeCatalog(), [makePullRequest()], previous, [observation({ status: 'completed' })]);
  assert.deepEqual(result.dispatches, []);
  assert.deepEqual(result.state, [{ ...previous[0], status: 'completed' }]);
});

test('pending state fails closed without a matching exact-SHA observation', () => {
  assert.throws(() => plan(makeCatalog(), [makePullRequest()], [state()], []),
    (error) => error.code === 'invalid-poll-input');
  assert.throws(() => plan(makeCatalog(), [makePullRequest()], [state()], [observation({ sha: shaB })]),
    (error) => error.code === 'invalid-poll-input');
});

test('closed, draft, fork, and non-owner PRs do not run repository code', () => {
  const result = plan(makeCatalog(), [
    makePullRequest({ number: 8, author: 'andrewsetness' }),
    makePullRequest({ number: 9, headRepository: 'contributor/project-jira-api' }),
    makePullRequest({ number: 10, draft: true }),
    { ...makePullRequest({ number: 11 }), state: 'closed' },
  ]);
  assert.deepEqual(result.dispatches, []);
  assert.deepEqual(result.state, []);
});

test('only centrally approved implementations are polled', () => {
  const catalog = makeCatalog({ implementationId: 'future-unreviewed-implementation' });
  assert.deepEqual(listRoutinePullRequestPollRepositories(catalog), []);
  assert.deepEqual(planRoutinePullRequestPoll(catalog, [], [], [], now), {
    status: 'ready', dispatches: [], state: [],
  });
});

test('qualified profiles remain runnable after their evidence gate passes', () => {
  const result = plan(makeCatalog({ profileStatus: 'qualified' }), [makePullRequest()]);
  assert.equal(result.dispatches.length, 1);
  assert.equal(result.dispatches[0].headSha, shaA);
});

test('poll data must cover exactly the approved repository set', () => {
  assert.throws(() => planRoutinePullRequestPoll(makeCatalog(), [], [], [], now), /every and only approved repository/);
  assert.throws(() => planRoutinePullRequestPoll(makeCatalog(), [
    { repository: 'setnessconsulting/unapproved', pullRequests: [] },
  ], [], [], now), /every and only approved repository/);
});

test('duplicate prior-state entries fail closed', () => {
  assert.throws(() => plan(makeCatalog(), [], [
    state(),
    { ...state(), headSha: shaB },
  ]), /duplicate PR/);
});

test('dispatch correlation IDs in prior state must be controller-shaped UUIDv4 values', () => {
  assert.throws(() => plan(makeCatalog(), [], [state({ dispatchId: 'not-a-dispatch-id' })]),
    (error) => error.code === 'invalid-poll-state');
});

test('malformed PR entries fail closed instead of partially planning dispatches', () => {
  assert.throws(() => plan(makeCatalog(), [{ number: 7 }]), (error) => error.code === 'invalid-pr-request');
});
