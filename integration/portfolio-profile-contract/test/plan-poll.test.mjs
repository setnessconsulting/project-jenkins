import test from 'node:test';
import assert from 'node:assert/strict';
import {
  listRoutinePullRequestPollRepositories,
  planRoutinePullRequestPoll,
} from '../src/consumer.mjs';

const repository = 'setnessconsulting/project-jira-api';
const shaA = 'a'.repeat(40);
const shaB = 'b'.repeat(40);

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

function plan(catalog, pullRequests, previousState = []) {
  return planRoutinePullRequestPoll(catalog, [{ repository, pullRequests }], previousState);
}

test('polling is inert until the private control plane is explicitly active', () => {
  const catalog = makeCatalog({ controlPlaneStatus: 'planned' });
  assert.deepEqual(listRoutinePullRequestPollRepositories(catalog), []);
  const previousState = [{ repository, pullRequestNumber: 7, headSha: shaA }];
  assert.deepEqual(planRoutinePullRequestPoll(catalog, [], previousState), {
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
  }]);
  assert.deepEqual(result.state, []);
});

test('the last dispatched SHA is not queued again, but a changed SHA is', () => {
  const previous = [{ repository, pullRequestNumber: 7, headSha: shaA }];
  const unchanged = plan(makeCatalog(), [makePullRequest()], previous);
  assert.deepEqual(unchanged.dispatches, []);
  assert.deepEqual(unchanged.state, previous);

  const changed = plan(makeCatalog(), [makePullRequest({ sha: shaB })], previous);
  assert.equal(changed.dispatches.length, 1);
  assert.equal(changed.dispatches[0].headSha, shaB);
  // The controller records the new SHA only after downstream scheduling succeeds.
  assert.deepEqual(changed.state, previous);
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
  assert.deepEqual(planRoutinePullRequestPoll(catalog, [], []), {
    status: 'ready', dispatches: [], state: [],
  });
});

test('qualified profiles remain runnable after their evidence gate passes', () => {
  const result = plan(makeCatalog({ profileStatus: 'qualified' }), [makePullRequest()]);
  assert.equal(result.dispatches.length, 1);
  assert.equal(result.dispatches[0].headSha, shaA);
});

test('poll data must cover exactly the approved repository set', () => {
  assert.throws(() => planRoutinePullRequestPoll(makeCatalog(), [], []), /every and only approved repository/);
  assert.throws(() => planRoutinePullRequestPoll(makeCatalog(), [
    { repository: 'setnessconsulting/unapproved', pullRequests: [] },
  ], []), /every and only approved repository/);
});

test('duplicate prior-state entries fail closed', () => {
  assert.throws(() => plan(makeCatalog(), [], [
    { repository, pullRequestNumber: 7, headSha: shaA },
    { repository, pullRequestNumber: 7, headSha: shaB },
  ]), /duplicate PR/);
});

test('malformed PR entries fail closed instead of partially planning dispatches', () => {
  assert.throws(() => plan(makeCatalog(), [{ number: 7 }]), (error) => error.code === 'invalid-pr-request');
});
