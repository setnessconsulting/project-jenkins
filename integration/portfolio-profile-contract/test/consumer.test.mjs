import assert from 'node:assert/strict';
import test from 'node:test';

import {
  IMPLEMENTATIONS,
  ProfileRejection,
  resolveShadowExecution,
  validateProfileCatalog,
  verifyPullRequestHead,
} from '../src/consumer.mjs';

const sha = 'a'.repeat(40);

function catalog() {
  return {
    schemaVersion: 1,
    approvedImplementations: ['node22-foundation-v1'],
    profiles: [{
      id: 'example-foundation',
      implementationId: 'node22-foundation-v1',
      status: 'shadow',
      repositories: ['setnessconsulting/example-repository'],
      checkNames: ['jenkins-pr-gate'],
      requiredNodeVersion: '22.23.3',
      qualification: {
        requiredExactShaCases: 10,
        qualifiedExactShaCases: 0,
        state: 'not-started',
      },
    }],
    controlPlane: {
      repository: 'setnessconsulting/private-catalog',
      validationProfileId: 'private-catalog-validation',
      status: 'active',
    },
  };
}

function pr(overrides = {}) {
  return {
    number: 17,
    state: 'open',
    draft: false,
    head: {
      sha,
      repo: { full_name: 'setnessconsulting/example-repository' },
    },
    base: { repo: { full_name: 'setnessconsulting/example-repository' } },
    user: { login: 'setnessconsulting' },
    ...overrides,
  };
}

function rejectsCode(run, expectedCode) {
  assert.throws(run, (error) => error instanceof ProfileRejection && error.code === expectedCode);
}

test('validates the closed catalog and resolves centrally-owned static commands', () => {
  assert.deepEqual(validateProfileCatalog(catalog()), { profileCount: 1, implementationCount: 1 });
  const plan = resolveShadowExecution(catalog(), 'example-foundation', sha.toUpperCase());
  assert.equal(plan.repository, 'setnessconsulting/example-repository');
  assert.equal(plan.headSha, sha);
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.equal(plan.agentClass, 'setness-ephemeral');
  assert.equal(Object.isFrozen(plan.commands), true);
  assert.equal(Object.isFrozen(plan.commands[0]), true);
  assert.deepEqual(plan.commands, IMPLEMENTATIONS['node22-foundation-v1'].commands);
  assert.deepEqual(plan.commands, [
    ['npm', 'ci', '--ignore-scripts'],
    ['npm', 'run', 'check'],
    ['npm', 'test'],
    ['npm', 'run', 'verify'],
  ]);
});

test('rejects profile fields that could inject commands or credentials', () => {
  const input = catalog();
  input.profiles[0].commands = ['curl attacker.invalid'];
  rejectsCode(() => validateProfileCatalog(input), 'unexpected-field');
});

test('rejects unapproved implementation IDs even if profile data includes a command list', () => {
  const input = catalog();
  input.profiles[0].implementationId = 'shell-from-catalog';
  input.approvedImplementations.push('shell-from-catalog');
  rejectsCode(() => resolveShadowExecution(input, 'example-foundation', sha), 'implementation-not-installed');
});

test('unmapped and planned profiles cannot execute', () => {
  const unmapped = catalog();
  unmapped.profiles[0] = {
    id: 'example-foundation',
    status: 'unmapped',
    repositories: ['setnessconsulting/example-repository'],
    checkNames: [],
    qualification: { requiredExactShaCases: 0, qualifiedExactShaCases: 0, state: 'not-started' },
  };
  rejectsCode(() => resolveShadowExecution(unmapped, 'example-foundation', sha), 'profile-not-shadow');
  const planned = catalog();
  planned.profiles[0].status = 'planned';
  rejectsCode(() => resolveShadowExecution(planned, 'example-foundation', sha), 'profile-not-shadow');
});

test('rejects ambiguous profiles, missing required gate, and malformed SHA', () => {
  const ambiguous = catalog();
  ambiguous.profiles[0].repositories.push('setnessconsulting/another-repository');
  rejectsCode(() => resolveShadowExecution(ambiguous, 'example-foundation', sha), 'ambiguous-profile');
  const missingCheck = catalog();
  missingCheck.profiles[0].checkNames = ['some-other-check'];
  rejectsCode(() => resolveShadowExecution(missingCheck, 'example-foundation', sha), 'required-check-missing');
  rejectsCode(() => resolveShadowExecution(catalog(), 'example-foundation', 'main'), 'invalid-head-sha');
});

test('rejects a profile whose required Node.js runtime differs from the pinned agent', () => {
  const mismatched = catalog();
  mismatched.profiles[0].requiredNodeVersion = '22.14.0';
  rejectsCode(() => resolveShadowExecution(mismatched, 'example-foundation', sha), 'runtime-mismatch');
  const missing = catalog();
  delete missing.profiles[0].requiredNodeVersion;
  rejectsCode(() => resolveShadowExecution(missing, 'example-foundation', sha), 'runtime-mismatch');
});

test('accepts only exact, open, same-repository PR heads from allowlisted authors', () => {
  const verified = verifyPullRequestHead(pr(), {
    repository: 'setnessconsulting/example-repository',
    pullRequestNumber: 17,
    headSha: sha,
    allowedAuthors: ['setnessconsulting'],
  });
  assert.equal(verified.headSha, sha);
  assert.equal(verified.author, 'setnessconsulting');

  const stale = pr();
  stale.head.sha = 'b'.repeat(40);
  rejectsCode(() => verifyPullRequestHead(stale, {
    repository: 'setnessconsulting/example-repository', pullRequestNumber: 17,
    headSha: sha, allowedAuthors: ['setnessconsulting'],
  }), 'stale-or-untrusted-pr');

  const fork = pr();
  fork.head.repo.full_name = 'contributor/example-repository';
  rejectsCode(() => verifyPullRequestHead(fork, {
    repository: 'setnessconsulting/example-repository', pullRequestNumber: 17,
    headSha: sha, allowedAuthors: ['setnessconsulting'],
  }), 'stale-or-untrusted-pr');

  const unauthorized = pr();
  unauthorized.user.login = 'outside-contributor';
  rejectsCode(() => verifyPullRequestHead(unauthorized, {
    repository: 'setnessconsulting/example-repository', pullRequestNumber: 17,
    headSha: sha, allowedAuthors: ['setnessconsulting'],
  }), 'author-not-allowed');

  const malformed = pr();
  malformed.head.sha = 17;
  rejectsCode(() => verifyPullRequestHead(malformed, {
    repository: 'setnessconsulting/example-repository', pullRequestNumber: 17,
    headSha: sha, allowedAuthors: ['setnessconsulting'],
  }), 'stale-or-untrusted-pr');

  const malformedRepository = pr();
  malformedRepository.base.repo.full_name = 42;
  rejectsCode(() => verifyPullRequestHead(malformedRepository, {
    repository: 'setnessconsulting/example-repository', pullRequestNumber: 17,
    headSha: sha, allowedAuthors: ['setnessconsulting'],
  }), 'stale-or-untrusted-pr');

  const draft = pr();
  draft.draft = true;
  rejectsCode(() => verifyPullRequestHead(draft, {
    repository: 'setnessconsulting/example-repository', pullRequestNumber: 17,
    headSha: sha, allowedAuthors: ['setnessconsulting'],
  }), 'stale-or-untrusted-pr');
});

test('rejects qualified and fork claims without full evidence', () => {
  const overclaim = catalog();
  overclaim.profiles[0].status = 'qualified';
  overclaim.profiles[0].qualification.state = 'passed';
  rejectsCode(() => validateProfileCatalog(overclaim), 'qualification-overclaim');

  const forkOverclaim = catalog();
  forkOverclaim.profiles[0].forkSandboxQualification = { state: 'passed' };
  rejectsCode(() => validateProfileCatalog(forkOverclaim), 'fork-qualification-overclaim');
});
