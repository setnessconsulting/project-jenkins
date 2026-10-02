// Minimal versioned consumer representation of the canonical Test Platform
// documents, plus strict validation of the fields this adapter depends on.
//
// This file deliberately does NOT re-model Test Platform. It validates only
// the fields a consumer must enforce to fail closed. Canonical schema and
// semantics stay in project-test-platform (schemas/v1/contracts.schema.json).

const EXACT_SHA = /^[0-9a-f]{40,64}$/;
const REPOSITORY = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?\/[A-Za-z0-9._-]{1,100}$/;
const SUITE_ID = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;
const ENTRYPOINT = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;
const EXECUTOR_ID = /^[a-z0-9][a-z0-9-]{0,63}$/;
const DIAGNOSTIC_CODE = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;
const ARTIFACT_PATH = /^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$/;
const RECEIPT_ID = /^receipt:[0-9a-f]{24}$/;
const TRUST_CLASSES = [
  'pr-untrusted',
  'trusted-branch',
  'trusted-manual',
  'live-qualification',
];
const EXECUTION_STATUSES = [
  'passed',
  'failed',
  'agent-unavailable',
  'controller-unavailable',
  'timed-out',
  'cancelled',
  'stale-head',
  'checkout-sha-mismatch',
  'unsupported-capability',
  'rejected-trust',
  'malformed-result',
];
const EVIDENCE_CLASSES = [
  'static',
  'deterministic',
  'contract',
  'integration',
  'end-to-end',
  'adversarial-security',
  'live-qualification',
  'performance',
  'manual',
];

export class ContractRejection extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'ContractRejection';
    this.code = code;
  }
}

function reject(code, message) {
  throw new ContractRejection(code, message);
}

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function requireObject(value, label, code = 'malformed-document') {
  if (!isPlainObject(value)) reject(code, `${label} must be an object`);
  return value;
}

function requireExactKeys(value, keys, label) {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    reject(
      'unknown-field',
      `${label} must contain exactly [${expected.join(', ')}]; got [${actual.join(', ')}]`,
    );
  }
}

function requireString(value, label, pattern, { min = 1, max = 4096 } = {}) {
  if (typeof value !== 'string' || value.length < min || value.length > max) {
    reject('malformed-document', `${label} must be a bounded string`);
  }
  if (pattern && !pattern.test(value)) {
    reject('malformed-document', `${label} does not match its required identity shape`);
  }
  return value;
}

function requireExactSha(value, label) {
  return requireString(value, label, EXACT_SHA, { min: 40, max: 64 });
}

function requireInteger(value, label, min, max) {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
    reject('malformed-document', `${label} must be an integer within [${min}, ${max}]`);
  }
  return value;
}

function requireBoundedInteger(value, label, min, max) {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min) {
    reject('malformed-document', `${label} must be an integer of at least ${min}`);
  }
  if (value > max) {
    reject('unbounded-document', `${label} exceeds its declared bound of ${max}`);
  }
  return value;
}

function requireFiniteNonNegative(value, label) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    reject('malformed-document', `${label} must be a finite non-negative number`);
  }
  return value;
}

function requireArray(value, label, max) {
  if (!Array.isArray(value)) reject('malformed-document', `${label} must be an array`);
  if (value.length > max) reject('unbounded-document', `${label} exceeds its declared bound`);
  return value;
}

function requireStringArray(value, label, max) {
  return requireArray(value, label, max).map((item, index) =>
    requireString(item, `${label}[${index}]`),
  );
}

export function requireSupportedVersion(allowed, value, label) {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    reject(
      'unsupported-version',
      `${label} ${JSON.stringify(value)} is not supported; supported: ${allowed.join(', ')}`,
    );
  }
  return value;
}

function validateSuiteDefinition(suite, label) {
  requireObject(suite, label);
  requireString(suite.suite_id, `${label}.suite_id`, SUITE_ID);
  requireString(suite.entrypoint, `${label}.entrypoint`, ENTRYPOINT);
  requireString(suite.trust, `${label}.trust`);
  if (!TRUST_CLASSES.includes(suite.trust)) {
    reject('malformed-document', `${label}.trust is not a known execution trust class`);
  }
  requireInteger(suite.timeout_seconds, `${label}.timeout_seconds`, 1, 86400);
  requireStringArray(suite.evidence_classes, `${label}.evidence_classes`, 16);
  return suite;
}

function validatePlan(plan) {
  requireObject(plan, 'plan');
  requireString(plan.plan_id, 'plan.plan_id');
  requireString(plan.repository, 'plan.repository', REPOSITORY);
  requireExactSha(plan.sha, 'plan.sha');
  requireObject(plan.profile, 'plan.profile');
  requireString(plan.profile.profile_id, 'plan.profile.profile_id');
  requireString(plan.profile.version, 'plan.profile.version');
  requireString(plan.trust, 'plan.trust');
  if (!TRUST_CLASSES.includes(plan.trust)) {
    reject('malformed-document', 'plan.trust is not a known execution trust class');
  }
  requireString(plan.policy_version, 'plan.policy_version');
  const suites = requireArray(plan.suites, 'plan.suites', 256);
  if (suites.length === 0) reject('malformed-document', 'plan.suites must not be empty');
  suites.forEach((suite, index) => validateSuiteDefinition(suite, `plan.suites[${index}]`));
  return plan;
}

function validateEvidenceReference(reference, label) {
  requireObject(reference, label);
  requireExactKeys(
    reference,
    ['evidence_id', 'evidence_class', 'live', 'source', 'reference'],
    label,
  );
  requireString(reference.evidence_id, `${label}.evidence_id`);
  requireString(reference.evidence_class, `${label}.evidence_class`);
  if (typeof reference.live !== 'boolean') {
    reject('malformed-document', `${label}.live must be a boolean`);
  }
  requireString(reference.source, `${label}.source`);
  if (reference.reference === null) return reference;
  requireString(reference.reference, `${label}.reference`, ARTIFACT_PATH);
  const segments = reference.reference.split('/');
  if (segments.some((segment) => segment === '' || segment === '.' || segment === '..')) {
    reject('malformed-document', `${label}.reference must be a bounded relative path`);
  }
  return reference;
}

function validateReceipt(receipt, label) {
  requireObject(receipt, label);
  requireExactKeys(
    receipt,
    [
      'schema_version',
      'receipt_id',
      'plan_id',
      'repository',
      'sha',
      'profile',
      'suite_id',
      'executor',
      'trust',
      'result',
      'passed_tests',
      'failed_tests',
      'skipped_tests',
      'duration_seconds',
      'evidence',
      'tool_versions',
      'generated_at',
    ],
    label,
  );
  requireString(receipt.receipt_id, `${label}.receipt_id`, RECEIPT_ID);
  requireSupportedVersion(['1'], receipt.schema_version, `${label}.schema_version`);
  requireString(receipt.plan_id, `${label}.plan_id`);
  requireString(receipt.repository, `${label}.repository`, REPOSITORY);
  requireExactSha(receipt.sha, `${label}.sha`);
  requireObject(receipt.profile, `${label}.profile`);
  requireString(receipt.suite_id, `${label}.suite_id`, SUITE_ID);
  requireString(receipt.executor, `${label}.executor`, EXECUTOR_ID);
  requireString(receipt.trust, `${label}.trust`);
  requireInteger(receipt.passed_tests, `${label}.passed_tests`, 0, 10000000);
  requireInteger(receipt.failed_tests, `${label}.failed_tests`, 0, 10000000);
  requireInteger(receipt.skipped_tests, `${label}.skipped_tests`, 0, 10000000);
  requireFiniteNonNegative(receipt.duration_seconds, `${label}.duration_seconds`);
  requireArray(receipt.evidence, `${label}.evidence`, 64).forEach((item, index) =>
    validateEvidenceReference(item, `${label}.evidence[${index}]`),
  );
  requireArray(receipt.tool_versions, `${label}.tool_versions`, 32).forEach((item, index) => {
    requireObject(item, `${label}.tool_versions[${index}]`);
    requireString(item.name, `${label}.tool_versions[${index}].name`);
    requireString(item.version, `${label}.tool_versions[${index}].version`);
  });
  requireString(receipt.generated_at, `${label}.generated_at`);
  if (Number.isNaN(Date.parse(receipt.generated_at))) {
    reject('malformed-document', `${label}.generated_at must be an ISO-8601 timestamp`);
  }
  return receipt;
}

export function validateExecutionRequest(request, catalog) {
  requireObject(request, 'request');
  requireSupportedVersion(
    catalog.contract.request_schema_versions,
    request.schema_version,
    'request.schema_version',
  );
  requireString(request.contract_id, 'request.contract_id');
  if (request.contract_id !== catalog.contract.contract_id) {
    reject('contract-mismatch', `unsupported contract id ${request.contract_id}`);
  }
  if (request.contract_version !== catalog.contract.contract_version) {
    reject(
      'contract-mismatch',
      `unsupported contract version ${request.contract_version}; this controller is qualified for ${catalog.contract.contract_version}`,
    );
  }
  if (!['synthetic-qualification', 'controller-execution'].includes(request.execution_mode)) {
    reject('malformed-document', 'request.execution_mode is not a known mode');
  }
  requireString(request.policy_version, 'request.policy_version');
  requireInteger(request.max_execution_seconds, 'request.max_execution_seconds', 1, 604800);
  requireString(request.platform_version, 'request.platform_version');

  requireObject(request.head, 'request.head');
  requireString(request.head.repository, 'request.head.repository', REPOSITORY);
  requireExactSha(request.head.sha, 'request.head.sha');

  const plan = validatePlan(request.plan);
  requireSupportedVersion(
    catalog.contract.plan_schema_versions,
    request.plan_schema_version,
    'request.plan_schema_version',
  );
  if (request.plan_schema_version !== plan.schema_version) {
    reject('malformed-document', 'request plan schema version does not match the plan');
  }
  if (request.head.repository !== plan.repository) {
    reject(
      'repository-mismatch',
      `request head repository ${request.head.repository} does not match plan repository ${plan.repository}`,
    );
  }
  if (request.head.sha !== plan.sha) {
    reject(
      'sha-mismatch',
      `request head SHA ${request.head.sha} does not match plan SHA ${plan.sha}`,
    );
  }
  if (catalog.repositories.length > 0 && !catalog.repositories.includes(plan.repository)) {
    reject(
      'repository-mismatch',
      `repository ${plan.repository} is not approved for Jenkins execution on this controller`,
    );
  }

  requireObject(request.trust_grant, 'request.trust_grant');
  requireString(request.trust_grant.trust, 'request.trust_grant.trust');
  if (request.trust_grant.trust !== plan.trust) {
    reject('trust-escalation', 'trust grant does not match the plan trust class');
  }
  const grantedCapabilities = requireStringArray(
    request.trust_grant.capabilities,
    'request.trust_grant.capabilities',
    16,
  );
  const allowedForTrust = catalog.trust_capabilities[plan.trust];
  if (!allowedForTrust) reject('trust-escalation', `unknown trust class ${plan.trust}`);
  const overGranted = grantedCapabilities.filter((item) => !allowedForTrust.includes(item));
  if (overGranted.length > 0) {
    reject(
      'trust-escalation',
      `trust grant exceeds the ${plan.trust} ceiling: ${overGranted.join(', ')}`,
    );
  }

  const requestSuites = requireArray(request.suites, 'request.suites', 256);
  if (requestSuites.length !== plan.suites.length) {
    reject('malformed-document', 'request suite bindings must cover the planned suites');
  }
  request.suites.forEach((suite, index) => {
    requireString(suite.suite_id, `request.suites[${index}].suite_id`, SUITE_ID);
    requireString(suite.executor_id, `request.suites[${index}].executor_id`, EXECUTOR_ID);
    requireInteger(suite.timeout_seconds, `request.suites[${index}].timeout_seconds`, 1, 86400);
    requireStringArray(
      suite.required_capabilities,
      `request.suites[${index}].required_capabilities`,
      16,
    );
    requireStringArray(
      suite.evidence_classes,
      `request.suites[${index}].evidence_classes`,
      16,
    );
    const artifacts = requireArray(
      suite.artifacts,
      `request.suites[${index}].artifacts`,
      64,
    );
    artifacts.forEach((artifact, artifactIndex) => {
      const label = `request.suites[${index}].artifacts[${artifactIndex}]`;
      requireString(artifact.artifact_id, `${label}.artifact_id`);
      requireString(artifact.path, `${label}.path`, ARTIFACT_PATH);
      requireBoundedInteger(artifact.max_bytes, `${label}.max_bytes`, 1, catalog.limits.max_artifact_bytes);
      if (typeof artifact.live !== 'boolean') {
        reject('malformed-document', `${label}.live must be a boolean`);
      }
      requireString(artifact.evidence_class, `${label}.evidence_class`);
      if (!EVIDENCE_CLASSES.includes(artifact.evidence_class)) {
        reject('malformed-document', `${label}.evidence_class is not a known evidence class`);
      }
    });
  });
  requireStringArray(request.required_capabilities, 'request.required_capabilities', 32);

  const resultMapping = requireArray(request.result_mapping, 'request.result_mapping', 16);
  const mapped = new Set();
  for (const rule of resultMapping) {
    requireObject(rule, 'request.result_mapping[]');
    requireString(rule.status, 'request.result_mapping[].status');
    if (!EXECUTION_STATUSES.includes(rule.status)) {
      reject('malformed-document', `unknown outcome status ${rule.status}`);
    }
    if (mapped.has(rule.status)) {
      reject('malformed-document', `duplicate outcome status ${rule.status}`);
    }
    mapped.add(rule.status);
    requireString(rule.result, 'request.result_mapping[].result');
    if (rule.status !== 'passed' && rule.result === 'pass') {
      reject(
        'result-escalation',
        `outcome ${rule.status} may not be normalized to a pass result`,
      );
    }
    if (rule.status === 'passed' && rule.result !== 'pass') {
      reject('result-escalation', 'a passed outcome must normalize to a pass result');
    }
    if (rule.status === 'failed' && rule.result !== 'fail') {
      reject('result-escalation', 'a failed outcome must normalize to a fail result');
    }
  }
  if (!mapped.has('passed')) {
    reject('malformed-document', 'result mapping must define a passed outcome');
  }

  requireObject(request.cancellation, 'request.cancellation');
  for (const key of [
    'cancel_on_superseded_head',
    'cancel_on_newer_plan',
    'abandon_workspace_on_cancel',
  ]) {
    if (typeof request.cancellation[key] !== 'boolean') {
      reject('malformed-document', `request.cancellation.${key} must be a boolean`);
    }
  }
  requireObject(request.stale_head, 'request.stale_head');
  if (typeof request.stale_head.require_current_head !== 'boolean') {
    reject('malformed-document', 'request.stale_head.require_current_head must be a boolean');
  }
  if (!['blocked', 'not-evaluable'].includes(request.stale_head.on_stale_head)) {
    reject(
      'result-escalation',
      'stale-head handling may only normalize to blocked or not-evaluable',
    );
  }
  requireInteger(
    request.stale_head.max_head_age_seconds,
    'request.stale_head.max_head_age_seconds',
    0,
    604800,
  );
  return request;
}

export function validateExecutorResults(results, catalog) {
  const validated = requireArray(results, 'executor results', 256);
  return validated.map((result, index) => {
    const label = `executor results[${index}]`;
    requireObject(result, label);
    requireString(result.suite_id, `${label}.suite_id`, SUITE_ID);
    requireString(result.executor_id, `${label}.executor_id`, EXECUTOR_ID);
    requireString(result.status, `${label}.status`);
    if (!EXECUTION_STATUSES.includes(result.status)) {
      reject('malformed-document', `${label}.status is not a known outcome status`);
    }
    requireString(result.observed_repository, `${label}.observed_repository`, REPOSITORY);
    requireExactSha(result.observed_sha, `${label}.observed_sha`);
    requireInteger(result.passed_tests, `${label}.passed_tests`, 0, 10000000);
    requireInteger(result.failed_tests, `${label}.failed_tests`, 0, 10000000);
    requireInteger(result.skipped_tests, `${label}.skipped_tests`, 0, 10000000);
    requireFiniteNonNegative(result.duration_seconds, `${label}.duration_seconds`);
    if (result.duration_seconds > catalog.limits.max_execution_seconds) {
      reject('unbounded-document', `${label}.duration_seconds exceeds the bounded maximum`);
    }
    requireStringArray(result.artifacts, `${label}.artifacts`, 64).forEach((path, pathIndex) =>
      requireString(path, `${label}.artifacts[${pathIndex}]`, ARTIFACT_PATH),
    );
    result.tool_versions.forEach((tool, toolIndex) => {
      requireObject(tool, `${label}.tool_versions[${toolIndex}]`);
      requireString(tool.name, `${label}.tool_versions[${toolIndex}].name`);
      requireString(tool.version, `${label}.tool_versions[${toolIndex}].version`);
    });
    if (result.diagnostics !== undefined) {
      requireArray(result.diagnostics, `${label}.diagnostics`, 32).forEach((item, itemIndex) => {
        const diagnosticLabel = `${label}.diagnostics[${itemIndex}]`;
        requireObject(item, diagnosticLabel);
        requireString(item.code, `${diagnosticLabel}.code`, DIAGNOSTIC_CODE);
        requireString(item.severity, `${diagnosticLabel}.severity`);
        requireString(item.message, `${diagnosticLabel}.message`, undefined, {
          min: 1,
          max: catalog.limits.max_diagnostic_message_length,
        });
      });
    }
    return result;
  });
}

export function validateReceiptSubmission(submission, catalog) {
  requireObject(submission, 'submission');
  requireSupportedVersion(
    catalog.contract.submission_schema_versions,
    submission.schema_version,
    'submission.schema_version',
  );
  if (submission.contract_id !== catalog.contract.contract_id) {
    reject('contract-mismatch', `unsupported contract id ${submission.contract_id}`);
  }
  if (submission.contract_version !== catalog.contract.contract_version) {
    reject('contract-mismatch', `unsupported contract version ${submission.contract_version}`);
  }
  if (!['synthetic', 'controller-recorded', 'live'].includes(submission.evidence_origin)) {
    reject('malformed-document', 'submission.evidence_origin is not a known origin');
  }
  if (!['synthetic-qualification', 'controller-execution'].includes(submission.execution_mode)) {
    reject('malformed-document', 'submission.execution_mode is not a known mode');
  }
  requireString(submission.generated_at, 'submission.generated_at');
  // Echoed verbatim from the request by the adapter; the consumer compares it
  // against the request it issued and refuses a divergent revision.
  requireString(submission.platform_version, 'submission.platform_version');
  const outcomes = requireArray(submission.outcomes, 'submission.outcomes', 256);
  if (outcomes.length === 0) reject('malformed-document', 'submission.outcomes must not be empty');
  const seen = new Set();
  outcomes.forEach((outcome, index) => {
    const label = `submission.outcomes[${index}]`;
    requireObject(outcome, label);
    requireSupportedVersion(['1'], outcome.schema_version, `${label}.schema_version`);
    requireString(outcome.suite_id, `${label}.suite_id`, SUITE_ID);
    requireString(outcome.executor_id, `${label}.executor_id`, EXECUTOR_ID);
    requireString(outcome.status, `${label}.status`);
    if (!EXECUTION_STATUSES.includes(outcome.status)) {
      reject('malformed-document', `${label}.status is not a known outcome status`);
    }
    if (seen.has(outcome.suite_id)) {
      reject('malformed-document', `duplicate outcome for suite ${outcome.suite_id}`);
    }
    seen.add(outcome.suite_id);
    requireObject(outcome.observed_head, `${label}.observed_head`);
    requireString(outcome.observed_head.repository, `${label}.observed_head.repository`, REPOSITORY);
    requireExactSha(outcome.observed_head.sha, `${label}.observed_head.sha`);
    validateReceipt(outcome.receipt, `${label}.receipt`);
  });
  return submission;
}

export { EXECUTION_STATUSES, TRUST_CLASSES };
