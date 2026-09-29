import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const adapterPath = fileURLToPath(new URL('../src/plan-poll.mjs', import.meta.url));
const sha = 'c'.repeat(40);
const repository = 'setnessconsulting/example-repository';

function catalog(status = 'active') {
  return {
    schemaVersion: 1,
    approvedImplementations: ['node22-verify-clean-checkout-v1'],
    profiles: [{
      id: 'example-clean-checkout',
      implementationId: 'node22-verify-clean-checkout-v1',
      status: 'shadow',
      repositories: [repository],
      checkNames: ['jenkins-pr-gate'],
      requiredNodeVersion: '22.14.0',
      qualification: {
        requiredExactShaCases: 10,
        qualifiedExactShaCases: 0,
        state: 'in-progress',
      },
    }],
    controlPlane: {
      repository: 'setnessconsulting/project-jenkins-config',
      validationProfileId: 'private-catalog-validation',
      status,
    },
  };
}

function pullRequest() {
  return {
    number: 4,
    state: 'open',
    draft: false,
    head: { sha, repo: { full_name: repository } },
    base: { repo: { full_name: repository } },
    user: { login: 'setnessconsulting' },
  };
}

function invoke(input, { args = [], rawInput } = {}) {
  return spawnSync(process.execPath, [adapterPath, ...args], {
    input: rawInput ?? JSON.stringify(input),
    encoding: 'utf8',
    timeout: 5000,
    maxBuffer: 3 * 1024 * 1024,
    windowsHide: true,
  });
}

test('targets mode returns only active, centrally supported profile repositories', () => {
  const result = invoke({ mode: 'targets', catalog: catalog() });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {
    status: 'ready',
    repositories: [repository],
    dispatches: [],
    state: [],
  });
});

test('plan mode emits an exact-SHA owner PR dispatch without caller-supplied commands', () => {
  const result = invoke({
    mode: 'plan',
    catalog: catalog(),
    pullRequestsByRepository: [{ repository, pullRequests: [pullRequest()] }],
    previousState: [],
  });
  assert.equal(result.status, 0, result.stderr);
  const parsed = JSON.parse(result.stdout);
  assert.equal(parsed.dispatches.length, 1);
  assert.deepEqual(parsed.dispatches[0], {
    repository,
    pullRequestNumber: 4,
    headSha: sha,
    profileId: 'example-clean-checkout',
  });
  assert.equal(JSON.stringify(parsed).includes('commands'), false);
});

test('planner fails closed on malformed input, oversized data, and caller arguments', () => {
  const malformed = invoke(null, { rawInput: '{bad json' });
  assert.equal(malformed.status, 2);
  assert.deepEqual(JSON.parse(malformed.stderr), { status: 'rejected', code: 'invalid-json' });

  const oversized = invoke(null, { rawInput: ' '.repeat(2 * 1024 * 1024 + 1) });
  assert.equal(oversized.status, 2);
  assert.deepEqual(JSON.parse(oversized.stderr), { status: 'rejected', code: 'request-too-large' });

  const withArgument = invoke({ mode: 'targets', catalog: catalog() }, { args: ['--anything'] });
  assert.equal(withArgument.status, 2);
  assert.deepEqual(JSON.parse(withArgument.stderr), { status: 'rejected', code: 'unexpected-arguments' });
});
