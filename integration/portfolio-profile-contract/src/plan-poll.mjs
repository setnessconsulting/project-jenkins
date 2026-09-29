import {
  listRoutinePullRequestPollRepositories,
  planRoutinePullRequestPoll,
  ProfileRejection,
} from './consumer.mjs';

const MAX_REQUEST_BYTES = 2 * 1024 * 1024;

class AdapterError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

function hasExactKeys(value, expected) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === expected.size
    && Object.keys(value).every((key) => expected.has(key));
}

async function readInput() {
  const chunks = [];
  let byteLength = 0;
  for await (const chunk of process.stdin) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    byteLength += buffer.length;
    if (byteLength > MAX_REQUEST_BYTES) throw new AdapterError('request-too-large');
    chunks.push(buffer);
  }
  if (byteLength === 0) throw new AdapterError('empty-request');
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new AdapterError('invalid-json');
  }
}

async function main() {
  if (process.argv.length !== 2) throw new AdapterError('unexpected-arguments');
  const input = await readInput();
  if (input?.mode === 'targets') {
    if (!hasExactKeys(input, new Set(['mode', 'catalog']))) {
      throw new AdapterError('invalid-request-envelope');
    }
    const repositories = listRoutinePullRequestPollRepositories(input.catalog);
    process.stdout.write(`${JSON.stringify({
      status: input.catalog.controlPlane.status === 'active' ? 'ready' : 'inactive',
      repositories,
      dispatches: [],
      state: [],
    })}\n`);
    return;
  }
  if (input?.mode !== 'plan'
      || !hasExactKeys(input, new Set(['mode', 'catalog', 'pullRequestsByRepository', 'previousState']))) {
    throw new AdapterError('invalid-request-envelope');
  }
  const plan = planRoutinePullRequestPoll(
    input.catalog,
    input.pullRequestsByRepository,
    input.previousState,
  );
  process.stdout.write(`${JSON.stringify(plan)}\n`);
}

main().catch((error) => {
  const code = typeof error?.code === 'string' && /^[a-z0-9-]{1,64}$/.test(error.code)
    ? error.code
    : error instanceof ProfileRejection ? error.code : 'poll-plan-rejected';
  process.stderr.write(`${JSON.stringify({ status: 'rejected', code })}\n`);
  process.exitCode = 2;
});
