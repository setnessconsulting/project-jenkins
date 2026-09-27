// Trusted Jenkins consumer adapter for Test Platform execution contracts.
//
// The adapter is centrally maintained logic. It accepts structured, approved
// data only: it never interpolates repository-controlled text into a command,
// never resolves a credential, and never decides what an outcome means. The
// normalized result table ships inside the request, authored by Test Platform.
//
// It also cannot forge a receipt: receipt identity is re-derived here exactly
// as Test Platform derives it, and Test Platform re-derives it again on
// ingestion. Any divergence fails closed.

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  ContractRejection,
  validateExecutionRequest,
  validateExecutorResults,
  validateReceiptSubmission,
} from './wire.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));

// Outcomes whose meaning depends on which head was actually checked out. Any
// other outcome observed at a different head is a security failure.
const HEAD_DEPENDENT_STATUSES = new Set([
  'stale-head',
  'checkout-sha-mismatch',
  'cancelled',
]);

export const APPROVED_CATALOG_PATH = join(HERE, 'approved-catalog.json');

export function loadApprovedCatalog(path = APPROVED_CATALOG_PATH) {
  const catalog = JSON.parse(readFileSync(path, 'utf8'));
  if (!catalog.contract || !catalog.executors || !catalog.suites) {
    throw new ContractRejection('malformed-catalog', 'the approved catalog is incomplete');
  }
  return catalog;
}

function trustRank(catalog, trust) {
  const rank = catalog.trust_rank[trust];
  if (typeof rank !== 'number') {
    throw new ContractRejection('trust-escalation', `unknown trust class ${trust}`);
  }
  return rank;
}

// Python renders an integral float as "N.0" and an integer as "N". The
// semantic payload mixes both, so float-valued fields are tagged explicitly
// instead of being guessed from the JavaScript number type.
export class PyFloat {
  constructor(value) {
    this.value = value;
  }
}

function pyFloatLiteral(value) {
  if (Number.isInteger(value)) return `${value}.0`;
  const rendered = String(value);
  if (!rendered.includes('e')) return rendered;
  return rendered.replace('e+', 'e').replace('e', 'e+');
}

export function canonicalJson(value) {
  if (value instanceof PyFloat) return pyFloatLiteral(value.value);
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  const keys = Object.keys(value).sort();
  return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
}

export function semanticHash(value) {
  return createHash('sha256').update(canonicalJson(value), 'utf8').digest('hex');
}

export function buildReceiptId(payload) {
  return `receipt:${semanticHash(payload).slice(0, 24)}`;
}

// --- request verification ---------------------------------------------------

export function verifyRequest(request, catalog = loadApprovedCatalog()) {
  validateExecutionRequest(request, catalog);

  const plan = request.plan;
  const rank = trustRank(catalog, plan.trust);
  const bindings = new Map();
  for (const binding of request.suites) bindings.set(binding.suite_id, binding);
  if (request.suites.length > catalog.limits.max_suites) {
    throw new ContractRejection('unbounded-document', 'request exceeds the bounded suite count');
  }

  const resolutions = [];
  for (const suite of plan.suites) {
    const approved = catalog.suites[suite.suite_id];
    if (!approved) {
      throw new ContractRejection(
        'unapproved-suite',
        `suite ${suite.suite_id} has no approved Jenkins executor mapping`,
      );
    }
    const binding = bindings.get(suite.suite_id);
    if (suite.entrypoint !== approved.entrypoint || binding.entrypoint !== approved.entrypoint) {
      throw new ContractRejection(
        'unapproved-entrypoint',
        `suite ${suite.suite_id} entrypoint does not match the approved Jenkins mapping`,
      );
    }
    if (binding.executor_id !== approved.executor_id) {
      throw new ContractRejection(
        'unapproved-executor',
        `suite ${suite.suite_id} requests an executor this controller does not approve`,
      );
    }
    if (trustRank(catalog, suite.trust) > rank) {
      throw new ContractRejection(
        'trust-escalation',
        `suite ${suite.suite_id} requires higher trust than ${plan.trust}`,
      );
    }
    if (suite.timeout_seconds > approved.timeout_seconds) {
      throw new ContractRejection(
        'unbounded-document',
        `suite ${suite.suite_id} timeout exceeds the approved bounded timeout`,
      );
    }
    if (suite.timeout_seconds > catalog.limits.max_suite_timeout_seconds) {
      throw new ContractRejection(
        'unbounded-document',
        `suite ${suite.suite_id} timeout exceeds the controller maximum`,
      );
    }

    const executor = catalog.executors[approved.executor_id];
    if (!executor) {
      throw new ContractRejection(
        'unapproved-executor',
        `executor ${approved.executor_id} is not configured on this controller`,
      );
    }
    if (trustRank(catalog, plan.trust) > trustRank(catalog, executor.max_trust)) {
      throw new ContractRejection(
        'trust-escalation',
        `executor ${executor.executor_id} cannot execute trust class ${plan.trust}`,
      );
    }
    const missing = approved.required_capabilities.filter(
      (capability) => !executor.capabilities.includes(capability),
    );
    if (missing.length > 0) {
      throw new ContractRejection(
        'unsupported-capability',
        `executor ${executor.executor_id} lacks: ${missing.join(', ')}`,
      );
    }
    if (plan.trust !== 'live-qualification') {
      const liveSurfaces = suite.evidence_classes.includes('live-qualification')
        || binding.artifacts.some((artifact) => artifact.live);
      if (liveSurfaces) {
        throw new ContractRejection(
          'trust-escalation',
          `suite ${suite.suite_id} requests live qualification surfaces under ${plan.trust}`,
        );
      }
    }
    if (binding.artifacts.length > catalog.limits.max_artifacts_per_suite) {
      throw new ContractRejection(
        'unbounded-document',
        `suite ${suite.suite_id} exceeds the bounded artifact declaration count`,
      );
    }
    const approvedEvidenceClasses = new Set(binding.evidence_classes);
    for (const artifact of binding.artifacts) {
      if (!approvedEvidenceClasses.has(artifact.evidence_class)) {
        throw new ContractRejection(
          'unapproved-evidence-class',
          `artifact ${artifact.artifact_id} declares evidence class ${artifact.evidence_class}, which suite ${suite.suite_id} does not approve`,
        );
      }
    }

    const profile = catalog.executor_profiles[approved.executor_id];
    if (!profile) {
      throw new ContractRejection(
        'unsupported-capability',
        `executor ${approved.executor_id} has no approved execution profile on this controller`,
      );
    }
    resolutions.push({
      suite_id: suite.suite_id,
      executor_id: approved.executor_id,
      agent_class: executor.agent_class,
      workspace: profile.workspace,
      // The command is Jenkins-owned and static. It is never derived from, and
      // never parameterized by, any repository-controlled value.
      command_tokens: [...profile.argv],
      timeout_seconds: approved.timeout_seconds,
      artifacts: binding.artifacts.map((artifact) => ({
        artifact_id: artifact.artifact_id,
        path: artifact.path,
        max_bytes: artifact.max_bytes,
        live: artifact.live,
        evidence_class: artifact.evidence_class,
      })),
    });
  }

  const totalTimeout = resolutions.reduce(
    (total, resolution) => total + resolution.timeout_seconds,
    0,
  );
  if (totalTimeout > catalog.limits.max_execution_seconds) {
    throw new ContractRejection(
      'unbounded-document',
      'approved suite timeouts exceed the bounded maximum execution time',
    );
  }

  return {
    accepted: true,
    contract_id: request.contract_id,
    contract_version: request.contract_version,
    plan_id: plan.plan_id,
    repository: plan.repository,
    sha: plan.sha,
    trust: plan.trust,
    execution_mode: request.execution_mode,
    resolved: resolutions,
  };
}

// --- submission construction ------------------------------------------------

function normalizeResult(request, resolution, result, generatedAt) {
  const rule = request.result_mapping.find((entry) => entry.status === result.status);
  if (!rule) {
    throw new ContractRejection(
      'unsupported-version',
      `the request defines no normalized result for outcome ${result.status}`,
    );
  }
  if (result.executor_id !== resolution.executor_id) {
    throw new ContractRejection(
      'unapproved-executor',
      `suite ${result.suite_id} reported an executor this controller did not run`,
    );
  }
  if (result.passed_tests + result.failed_tests + result.skipped_tests > 10000000) {
    throw new ContractRejection('unbounded-document', `suite ${result.suite_id} counts are unbounded`);
  }
  if (rule.result === 'pass' && result.failed_tests > 0) {
    throw new ContractRejection(
      'result-escalation',
      `suite ${result.suite_id} reported failing tests as a pass`,
    );
  }

  const declared = new Map(resolution.artifacts.map((item) => [item.path, item]));
  const evidence = result.artifacts.map((path) => {
    const artifact = declared.get(path);
    if (!artifact) {
      throw new ContractRejection(
        'undeclared-artifact',
        `suite ${result.suite_id} handed off undeclared artifact ${path}`,
      );
    }
    return {
      evidence_id: `${result.suite_id}.${artifact.artifact_id}`,
      evidence_class: artifact.evidence_class,
      live: artifact.live,
      source: 'jenkins',
      reference: path,
    };
  });

  const payload = {
    plan_id: request.plan.plan_id,
    repository: request.plan.repository,
    sha: request.plan.sha,
    profile: {
      profile_id: request.plan.profile.profile_id,
      version: request.plan.profile.version,
    },
    suite_id: result.suite_id,
    executor: result.executor_id,
    trust: request.plan.trust,
    result: rule.result,
    passed_tests: result.passed_tests,
    failed_tests: result.failed_tests,
    skipped_tests: result.skipped_tests,
    duration_seconds: new PyFloat(result.duration_seconds),
    evidence,
    tool_versions: result.tool_versions,
  };

  return {
    status: result.status,
    observed_head: {
      repository: result.observed_repository,
      sha: result.observed_sha,
    },
    receipt: {
      schema_version: '1',
      receipt_id: buildReceiptId(payload),
      plan_id: payload.plan_id,
      repository: payload.repository,
      sha: payload.sha,
      profile: payload.profile,
      suite_id: payload.suite_id,
      executor: payload.executor,
      trust: payload.trust,
      result: payload.result,
      passed_tests: payload.passed_tests,
      failed_tests: payload.failed_tests,
      skipped_tests: payload.skipped_tests,
      duration_seconds: result.duration_seconds,
      evidence,
      tool_versions: payload.tool_versions,
      generated_at: generatedAt,
    },
    diagnostics: result.diagnostics ?? [],
  };
}

export function buildSubmission(
  request,
  results,
  {
    catalog = loadApprovedCatalog(),
    evidenceOrigin = 'synthetic',
    generatedAt = new Date().toISOString(),
  } = {},
) {
  const resolution = verifyRequest(request, catalog);
  const validated = validateExecutorResults(results, catalog);
  const bySuite = new Map(validated.map((result) => [result.suite_id, result]));

  const planned = request.plan.suites.map((suite) => suite.suite_id);
  const missing = planned.filter((suiteId) => !bySuite.has(suiteId));
  if (missing.length > 0) {
    throw new ContractRejection(
      'incomplete-execution',
      `no normalized result was reported for: ${missing.join(', ')}`,
    );
  }
  const unexpected = validated.map((result) => result.suite_id).filter(
    (suiteId) => !planned.includes(suiteId),
  );
  if (unexpected.length > 0) {
    throw new ContractRejection(
      'unapproved-suite',
      `results reported unplanned suites: ${unexpected.join(', ')}`,
    );
  }

  const liveOnly = evidenceOrigin === 'live';
  if (liveOnly && (request.execution_mode !== 'controller-execution' || request.plan.trust !== 'live-qualification')) {
    throw new ContractRejection(
      'trust-escalation',
      'a live evidence origin requires controller execution under live-qualification trust',
    );
  }
  if (request.execution_mode === 'synthetic-qualification' && evidenceOrigin !== 'synthetic') {
    throw new ContractRejection(
      'trust-escalation',
      'a synthetic execution mode must use a synthetic evidence origin',
    );
  }

  const outcomes = resolution.resolved.map((entry) => {
    const result = bySuite.get(entry.suite_id);
    const normalized = normalizeResult(request, entry, result, generatedAt);
    if (normalized.observed_head.repository !== request.plan.repository) {
      throw new ContractRejection(
        'repository-mismatch',
        `suite ${entry.suite_id} observed ${normalized.observed_head.repository}`,
      );
    }
    if (normalized.observed_head.sha !== request.plan.sha) {
      // A mismatched head is only ever reported, never accepted. A suite that
      // claims a pass or a real test failure at the wrong head is a security
      // failure, not a stale-head report.
      const reportable = HEAD_DEPENDENT_STATUSES.has(normalized.status);
      if (!reportable || !request.stale_head.require_current_head) {
        throw new ContractRejection(
          'sha-mismatch',
          `suite ${entry.suite_id} observed SHA ${normalized.observed_head.sha} but the plan binds ${request.plan.sha}`,
        );
      }
      if (normalized.status !== 'cancelled') {
        normalized.status = 'stale-head';
        normalized.receipt.result = request.stale_head.on_stale_head;
        // The result override changes the receipt content, so the receipt
        // identity must be re-derived to stay bound to the final result.
        const { schema_version: _schema, receipt_id: _id, generated_at: _at, ...payload } = normalized.receipt;
        normalized.receipt.receipt_id = buildReceiptId(payload);
      }
    }
    return {
      schema_version: '1',
      suite_id: entry.suite_id,
      executor_id: entry.executor_id,
      status: normalized.status,
      observed_head: normalized.observed_head,
      receipt: normalized.receipt,
      diagnostics: normalized.diagnostics,
    };
  });

  const submission = {
    schema_version: '1',
    contract_id: request.contract_id,
    contract_version: request.contract_version,
    plan_id: request.plan.plan_id,
    head: {
      repository: request.plan.repository,
      sha: request.plan.sha,
    },
    execution_mode: request.execution_mode,
    evidence_origin: liveOnly ? 'live' : evidenceOrigin,
    outcomes,
    generated_at: generatedAt,
  };
  validateReceiptSubmission(submission, catalog);
  return submission;
}

export { ContractRejection };
