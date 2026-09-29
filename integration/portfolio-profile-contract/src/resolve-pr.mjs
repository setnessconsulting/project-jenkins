import {
  resolveAuthorizedShadowPullRequestForRepository,
} from './consumer.mjs';

const MAX_REQUEST_BYTES = 1024 * 1024;
const TRUSTED_SHADOW_AUTHORS = Object.freeze(['setnessconsulting']);
const INPUT_KEYS = new Set(['catalog', 'pr', 'request']);
const REQUEST_KEYS = new Set(['repository', 'pullRequestNumber', 'headSha']);

class AdapterError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

function hasExactKeys(value, keys) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === keys.size
    && Object.keys(value).every((key) => keys.has(key));
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

function resolveForRepository(catalog, pr, request) {
  if (typeof request.repository !== 'string') {
    throw new AdapterError('invalid-repository');
  }
  return resolveAuthorizedShadowPullRequestForRepository(catalog, pr, {
    ...request,
    allowedAuthors: TRUSTED_SHADOW_AUTHORS,
  });
}

async function main() {
  if (process.argv.length !== 2) throw new AdapterError('unexpected-arguments');
  const input = await readInput();
  if (!hasExactKeys(input, INPUT_KEYS) || !hasExactKeys(input.request, REQUEST_KEYS)) {
    throw new AdapterError('invalid-request-envelope');
  }

  const plan = resolveForRepository(input.catalog, input.pr, input.request);
  process.stdout.write(`${JSON.stringify({ status: 'accepted', plan })}\n`);
}

main().catch((error) => {
  const code = typeof error?.code === 'string' && /^[a-z0-9-]{1,64}$/.test(error.code)
    ? error.code
    : 'profile-rejected';
  process.stderr.write(`${JSON.stringify({ status: 'rejected', code })}\n`);
  process.exitCode = 2;
});
