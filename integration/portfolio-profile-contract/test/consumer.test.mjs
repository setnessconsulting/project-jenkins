import assert from 'node:assert/strict';
import test from 'node:test';

import * as profileConsumer from '../src/consumer.mjs';

const {
  IMPLEMENTATIONS,
  ProfileRejection,
  ROUTINE_DISPATCH_IMPLEMENTATIONS,
  resolveAuthorizedShadowPullRequest,
  resolveAuthorizedShadowPullRequestForRepository,
  validateProfileCatalog,
  verifyPullRequestHead,
} = profileConsumer;

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

function resolve(input = catalog(), {
  profileId = 'example-foundation',
  prOverrides = {},
  ...requestOverrides
} = {}) {
  return resolveAuthorizedShadowPullRequest(input, profileId, pr(prOverrides), {
    repository: 'setnessconsulting/example-repository',
    pullRequestNumber: 17,
    headSha: sha,
    allowedAuthors: ['setnessconsulting'],
    ...requestOverrides,
  });
}

test('validates the closed catalog and resolves centrally-owned static commands', () => {
  assert.equal(Object.hasOwn(profileConsumer, 'resolveShadowExecution'), false);
  assert.deepEqual(validateProfileCatalog(catalog()), { profileCount: 1, implementationCount: 1 });
  const plan = resolve(catalog(), { headSha: sha.toUpperCase() });
  assert.equal(plan.repository, 'setnessconsulting/example-repository');
  assert.equal(plan.headSha, sha);
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.equal(plan.agentClass, 'setness-ephemeral');
  assert.equal(plan.nodeVersion, '22.23.3');
  assert.equal(plan.npmVersion, '10.9.9');
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

test('resolves the centrally pinned Node 24 lint, type, and test implementation', () => {
  const input = catalog();
  input.approvedImplementations.push('node24-lint-typescript-test-v1');
  input.profiles[0].implementationId = 'node24-lint-typescript-test-v1';
  input.profiles[0].requiredNodeVersion = '24.21.0';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-node24-ephemeral');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.equal(plan.nodeVersion, '24.21.0');
  assert.equal(Object.hasOwn(plan, 'npmVersion'), false);
  assert.deepEqual(plan.commands, [
    ['npm', 'ci'],
    ['npm', 'run', 'lint'],
    ['node_modules/.bin/tsc', '--noEmit'],
    ['npm', 'test'],
  ]);

  input.profiles[0].requiredNodeVersion = '24.21.1';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

test('resolves the clean-checkout workflow only on its exactly pinned Node 22.14 agent', () => {
  const input = catalog();
  input.approvedImplementations.push('node22-verify-clean-checkout-v1');
  input.profiles[0].implementationId = 'node22-verify-clean-checkout-v1';
  input.profiles[0].requiredNodeVersion = '22.14.0';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-node22-14-ephemeral');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.deepEqual(plan.commands, [
    ['npm', 'ci'],
    ['npm', 'run', 'verify'],
    ['npm', 'run', 'verify:clean-checkout'],
  ]);

  input.profiles[0].requiredNodeVersion = '22.23.3';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

test('resolves the Python 3.12 Test Platform workflow on its exactly pinned agent', () => {
  const input = catalog();
  input.approvedImplementations.push('python312-test-platform-v1');
  input.profiles[0].implementationId = 'python312-test-platform-v1';
  delete input.profiles[0].requiredNodeVersion;
  input.profiles[0].requiredPythonVersion = '3.12.14';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-python312-ephemeral');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.equal(plan.pythonVersion, '3.12.14');
  assert.equal(Object.hasOwn(plan, 'nodeVersion'), false);
  assert.deepEqual(plan.commands, [
    ['python', '-m', 'pip', 'install', '-e', '.[dev]'],
    ['python', '-m', 'test_platform.verify'],
  ]);

  input.profiles[0].requiredPythonVersion = '3.12.13';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
  input.profiles[0].requiredPythonVersion = '3.12.14';
  input.profiles[0].requiredNodeVersion = '22.23.3';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

test('resolves the Game AI Playtest Lab workflow to its pinned Python 3.12 command vectors', () => {
  const input = catalog();
  input.approvedImplementations.push('python312-playtest-lab-v1');
  input.profiles[0].implementationId = 'python312-playtest-lab-v1';
  delete input.profiles[0].requiredNodeVersion;
  input.profiles[0].requiredPythonVersion = '3.12.14';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-python312-ephemeral');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.equal(plan.pythonVersion, '3.12.14');
  assert.equal(Object.hasOwn(plan, 'nodeVersion'), false);
  assert.deepEqual(plan.commands, [
    ['python', '-m', 'pip', 'install', '--upgrade', 'pip'],
    ['python', '-m', 'pip', 'install', '.[test]'],
    ['mkdir', '-p', '.frameworks'],
    [
      'git', 'clone', '--filter=blob:none',
      'https://github.com/gameworld-project/GameWorld.git',
      '.frameworks/gameworld-upstream',
    ],
    [
      'git', '-C', '.frameworks/gameworld-upstream',
      'checkout', '--detach', '3c26bdab436800fd61ef40543b64ca40d12c7e4a',
    ],
    ['python', '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py', '-v'],
  ]);
  assert.equal(ROUTINE_DISPATCH_IMPLEMENTATIONS.includes('python312-playtest-lab-v1'), false);

  input.profiles[0].requiredPythonVersion = '3.11.15';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
  input.profiles[0].requiredPythonVersion = '3.12.14';
  input.profiles[0].requiredNodeVersion = '22.23.3';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

test('rejects profile fields that could inject commands or credentials', () => {
  const input = catalog();
  input.profiles[0].commands = ['curl attacker.invalid'];
  rejectsCode(() => resolve(input), 'unexpected-field');
});

test('rejects unapproved implementation IDs even if profile data includes a command list', () => {
  const input = catalog();
  input.profiles[0].implementationId = 'shell-from-catalog';
  input.approvedImplementations.push('shell-from-catalog');
  rejectsCode(() => resolve(input), 'implementation-not-installed');
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
  rejectsCode(() => resolve(unmapped), 'profile-not-shadow');
  const planned = catalog();
  planned.profiles[0].status = 'planned';
  rejectsCode(() => resolve(planned), 'profile-not-shadow');
});

test('rejects ambiguous profiles, missing required gate, and malformed SHA', () => {
  const ambiguous = catalog();
  ambiguous.profiles[0].repositories.push('setnessconsulting/another-repository');
  rejectsCode(() => resolve(ambiguous), 'ambiguous-profile');
  const missingCheck = catalog();
  missingCheck.profiles[0].checkNames = ['some-other-check'];
  rejectsCode(() => resolve(missingCheck), 'required-check-missing');
  rejectsCode(() => resolve(catalog(), { headSha: 'main' }), 'invalid-pr-request');
});

test('rejects case-insensitive repository aliases within and across profiles', () => {
  const withinProfile = catalog();
  withinProfile.profiles[0].repositories.push('setnessconsulting/Example-Repository');
  rejectsCode(() => validateProfileCatalog(withinProfile), 'invalid-profile');

  const acrossProfiles = catalog();
  acrossProfiles.profiles.push({
    ...acrossProfiles.profiles[0],
    id: 'example-retired',
    status: 'retired',
    repositories: ['setnessconsulting/Example-Repository'],
  });
  rejectsCode(() => validateProfileCatalog(acrossProfiles), 'duplicate-repository-profile');
});

test('rejects a profile whose required Node.js runtime differs from the pinned agent', () => {
  const mismatched = catalog();
  mismatched.profiles[0].requiredNodeVersion = '22.14.0';
  rejectsCode(() => resolve(mismatched), 'runtime-mismatch');
  const missing = catalog();
  delete missing.profiles[0].requiredNodeVersion;
  rejectsCode(() => resolve(missing), 'runtime-mismatch');
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

test('returns executable commands only after PR identity and profile repository bind', () => {
  const execution = resolveAuthorizedShadowPullRequest(catalog(), 'example-foundation', pr(), {
    repository: 'setnessconsulting/example-repository',
    pullRequestNumber: 17,
    headSha: sha,
    allowedAuthors: ['setnessconsulting'],
  });
  assert.equal(execution.repository, 'setnessconsulting/example-repository');
  assert.equal(execution.headSha, sha);
  assert.equal(execution.pullRequestNumber, 17);
  assert.equal(execution.author, 'setnessconsulting');
  assert.deepEqual(execution.commands, IMPLEMENTATIONS['node22-foundation-v1'].commands);

  const mismatchedProfile = catalog();
  mismatchedProfile.profiles[0].repositories = ['setnessconsulting/another-repository'];
  rejectsCode(() => resolveAuthorizedShadowPullRequest(
    mismatchedProfile,
    'example-foundation',
    pr(),
    {
      repository: 'setnessconsulting/example-repository',
      pullRequestNumber: 17,
      headSha: sha,
      allowedAuthors: ['setnessconsulting'],
    },
  ), 'profile-repository-mismatch');

  rejectsCode(() => resolveAuthorizedShadowPullRequest(catalog(), 'example-foundation', pr(), {
    repository: 'setnessconsulting/example-repository',
    pullRequestNumber: 17,
    headSha: sha,
    allowedAuthors: ['different-owner'],
  }), 'author-not-allowed');

  rejectsCode(() => resolve(catalog(), {
    prOverrides: {
      head: {
        sha,
        repo: { full_name: 'contributor/example-repository' },
      },
    },
  }), 'stale-or-untrusted-pr');

  rejectsCode(() => resolve(catalog(), {
    prOverrides: {
      head: {
        sha: 'b'.repeat(40),
        repo: { full_name: 'setnessconsulting/example-repository' },
      },
    },
  }), 'stale-or-untrusted-pr');
});

test('selects the profile from repository identity before authorizing the PR', () => {
  const execution = resolveAuthorizedShadowPullRequestForRepository(catalog(), pr(), {
    repository: 'setnessconsulting/EXAMPLE-REPOSITORY',
    pullRequestNumber: 17,
    headSha: sha,
    allowedAuthors: ['setnessconsulting'],
  });
  assert.equal(execution.repository, 'setnessconsulting/example-repository');
  assert.equal(execution.headSha, sha);

  rejectsCode(() => resolveAuthorizedShadowPullRequestForRepository(catalog(), pr(), {
    repository: 'setnessconsulting/another-repository',
    pullRequestNumber: 17,
    headSha: sha,
    allowedAuthors: ['setnessconsulting'],
  }), 'unknown-profile');

  const planned = catalog();
  planned.profiles[0].status = 'planned';
  rejectsCode(() => resolveAuthorizedShadowPullRequestForRepository(planned, pr(), {
    repository: 'setnessconsulting/example-repository',
    pullRequestNumber: 17,
    headSha: sha,
    allowedAuthors: ['setnessconsulting'],
  }), 'profile-not-shadow');
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
