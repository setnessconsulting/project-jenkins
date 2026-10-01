import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const adapterPath = fileURLToPath(new URL('../src/resolve-pr.mjs', import.meta.url));
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
        requiredExactShaCases: 4,
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

function pullRequest(overrides = {}) {
  return {
    number: 17,
    state: 'open',
    draft: false,
    head: { sha, repo: { full_name: 'setnessconsulting/example-repository' } },
    base: { repo: { full_name: 'setnessconsulting/example-repository' } },
    user: { login: 'setnessconsulting' },
    ...overrides,
  };
}

function invoke(input, { args = [], rawInput, timeout = 5000 } = {}) {
  return spawnSync(process.execPath, [adapterPath, ...args], {
    input: rawInput ?? JSON.stringify(input),
    encoding: 'utf8',
    timeout,
    maxBuffer: 1024 * 1024,
    windowsHide: true,
  });
}

function request() {
  return {
    repository: 'setnessconsulting/example-repository',
    pullRequestNumber: 17,
    headSha: sha,
  };
}

test('controller stdin adapter emits only the centrally defined plan for the exact owner PR head', () => {
  const result = invoke({ catalog: catalog(), pr: pullRequest(), request: request() });
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {
    status: 'accepted',
    plan: {
      profileId: 'example-foundation',
      repository: 'setnessconsulting/example-repository',
      headSha: sha,
      requiredCheck: 'jenkins-pr-gate',
      agentClass: 'setness-ephemeral',
      nodeVersion: '22.23.3',
      npmVersion: '10.9.9',
      commands: [
        ['npm', 'ci', '--ignore-scripts'],
        ['npm', 'run', 'check'],
        ['npm', 'test'],
        ['npm', 'run', 'verify'],
      ],
      pullRequestNumber: 17,
      author: 'setnessconsulting',
    },
  });
});

test('controller stdin adapter rejects outside authors, stale heads, and an injected author allowlist', () => {
  const outsideAuthor = invoke({
    catalog: catalog(),
    pr: pullRequest({ user: { login: 'outside-contributor' } }),
    request: request(),
  });
  assert.equal(outsideAuthor.status, 2);
  assert.deepEqual(JSON.parse(outsideAuthor.stderr), { status: 'rejected', code: 'author-not-allowed' });

  const staleHead = invoke({
    catalog: catalog(),
    pr: pullRequest({ head: { sha: 'b'.repeat(40), repo: { full_name: 'setnessconsulting/example-repository' } } }),
    request: request(),
  });
  assert.equal(staleHead.status, 2);
  assert.deepEqual(JSON.parse(staleHead.stderr), { status: 'rejected', code: 'stale-or-untrusted-pr' });

  const closedPullRequest = invoke({
    catalog: catalog(),
    pr: pullRequest({ state: 'closed' }),
    request: request(),
  });
  assert.equal(closedPullRequest.status, 2);
  assert.deepEqual(JSON.parse(closedPullRequest.stderr), { status: 'rejected', code: 'stale-or-untrusted-pr' });

  const widenedRequest = invoke({
    catalog: catalog(),
    pr: pullRequest({ user: { login: 'outside-contributor' } }),
    request: { ...request(), allowedAuthors: ['outside-contributor'] },
  });
  assert.equal(widenedRequest.status, 2);
  assert.deepEqual(JSON.parse(widenedRequest.stderr), { status: 'rejected', code: 'invalid-request-envelope' });
});

test('controller stdin adapter binds the requested repository to the PR source and catalog profile', () => {
  const unknownRepository = invoke({
    catalog: catalog(),
    pr: pullRequest(),
    request: { ...request(), repository: 'setnessconsulting/unmapped-repository' },
  });
  assert.equal(unknownRepository.status, 2);
  assert.deepEqual(JSON.parse(unknownRepository.stderr), { status: 'rejected', code: 'unknown-profile' });

  const mismatchedPullRequest = invoke({
    catalog: catalog(),
    pr: pullRequest({
      head: { sha, repo: { full_name: 'setnessconsulting/another-repository' } },
      base: { repo: { full_name: 'setnessconsulting/another-repository' } },
    }),
    request: request(),
  });
  assert.equal(mismatchedPullRequest.status, 2);
  assert.deepEqual(JSON.parse(mismatchedPullRequest.stderr), { status: 'rejected', code: 'stale-or-untrusted-pr' });
});

test('controller stdin adapter fails closed on malformed, oversized, or argument-controlled input', () => {
  const malformed = invoke(null, { rawInput: '{not-json' });
  assert.equal(malformed.status, 2);
  assert.deepEqual(JSON.parse(malformed.stderr), { status: 'rejected', code: 'invalid-json' });

  const oversized = invoke(null, { rawInput: ' '.repeat(1024 * 1024 + 1) });
  assert.equal(oversized.status, 2);
  assert.deepEqual(JSON.parse(oversized.stderr), { status: 'rejected', code: 'request-too-large' });

  const withArgument = invoke({ catalog: catalog(), pr: pullRequest(), request: request() }, { args: ['--allow-authors=*'] });
  assert.equal(withArgument.status, 2);
  assert.deepEqual(JSON.parse(withArgument.stderr), { status: 'rejected', code: 'unexpected-arguments' });
});
