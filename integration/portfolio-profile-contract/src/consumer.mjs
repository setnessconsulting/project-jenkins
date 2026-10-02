// Trusted resolver contract for portfolio profiles. Profile documents are
// untrusted data: they may select only an implementation already defined here.

const CATALOG_KEYS = new Set([
  'schemaVersion',
  'approvedImplementations',
  'profiles',
  'controlPlane',
]);
const PROFILE_KEYS = new Set([
  'id',
  'implementationId',
  'status',
  'repositories',
  'checkNames',
  'requiredNodeVersion',
  'requiredPythonVersion',
  'qualification',
  'forkSandboxQualification',
]);
const QUALIFICATION_KEYS = new Set([
  'requiredExactShaCases',
  'qualifiedExactShaCases',
  'state',
  'evidenceReference',
]);
const FORK_QUALIFICATION_KEYS = new Set(['state', 'evidenceReference']);
const CONTROL_PLANE_KEYS = new Set([
  'repository',
  'validationProfileId',
  'status',
]);
const PROFILE_STATUSES = new Set([
  'unmapped',
  'planned',
  'shadow',
  'qualified',
  'retired',
]);
const QUALIFICATION_STATES = new Set([
  'not-started',
  'in-progress',
  'passed',
  'failed',
]);

// Commands are intentionally static, centrally maintained argument vectors.
// No command, shell fragment, image, label, or environment value is taken from
// profile data. The package-specific implementation is added to the private
// catalog only after this contract is reviewed and merged.
export const IMPLEMENTATIONS = Object.freeze({
  'setness-web-ci-node22-v1': Object.freeze({
    agentClass: 'setness-web-ci-node22-ephemeral',
    nodeVersion: '22.23.3',
    npmVersion: '10.9.9',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'pwsh', '-File', 'scripts/verify-jenkins-fallback-contract.ps1']),
      Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'node', 'scripts/test-jenkins-fallback-runtime.mjs']),
      Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'ci']),
      Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'typecheck']),
      Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'lint']),
      Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'build']),
      Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'blog:validate']),
      Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'seo:baseline']),
      Object.freeze(['env', 'NEXT_PUBLIC_SITE_URL=https://setnessconsulting.com', 'npm', '--prefix', 'web', 'run', 'test']),
    ]),
  }),
  'node22-foundation-v1': Object.freeze({
    agentClass: 'setness-ephemeral',
    nodeVersion: '22.23.3',
    npmVersion: '10.9.9',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci', '--ignore-scripts']),
      Object.freeze(['npm', 'run', 'check']),
      Object.freeze(['npm', 'test']),
      Object.freeze(['npm', 'run', 'verify']),
    ]),
  }),
  'node22-github-api-foundation-v1': Object.freeze({
    agentClass: 'setness-web-ci-node22-ephemeral',
    nodeVersion: '22.23.3',
    npmVersion: '10.9.9',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci', '--ignore-scripts']),
      Object.freeze(['npm', 'run', 'check']),
      Object.freeze(['npm', 'test']),
      Object.freeze(['npm', 'run', 'verify']),
    ]),
  }),
  'jenkins-repository-contract': Object.freeze({
    agentClass: 'setness-web-ci-node22-ephemeral',
    nodeVersion: '22.23.3',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze([
        'node', '--test',
        'integration/portfolio-profile-contract/test/consumer.test.mjs',
        'integration/portfolio-profile-contract/test/plan-poll-cli.test.mjs',
        'integration/portfolio-profile-contract/test/plan-poll.test.mjs',
        'integration/portfolio-profile-contract/test/resolve-pr.test.mjs',
      ]),
      Object.freeze(['node', '--test', 'integration/test-platform-contract/test/adapter.test.mjs']),
    ]),
  }),
  'node22-verify-clean-checkout-v1': Object.freeze({
    agentClass: 'setness-node22-14-disposable-ephemeral',
    nodeVersion: '22.14.0',
    npmVersion: '10.9.2',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci']),
      Object.freeze(['npm', 'run', 'verify']),
      Object.freeze(['npm', 'run', 'verify:clean-checkout']),
    ]),
  }),
  'node2214-vercel-api-gitleaks-v1': Object.freeze({
    agentClass: 'setness-node22-14-disposable-ephemeral',
    nodeVersion: '22.14.0',
    npmVersion: '10.9.2',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze([
        'gitleaks', 'dir', '--redact', '--exit-code', '1',
        '--report-format', 'sarif', '--report-path', '/tmp/gitleaks.sarif', '.',
      ]),
      Object.freeze(['npm', 'ci', '--ignore-scripts']),
      Object.freeze(['npm', 'run', 'check']),
      Object.freeze(['npm', 'test']),
      Object.freeze(['npm', 'run', 'verify']),
    ]),
  }),
  'node2214-unity-api-maintenance-v1': Object.freeze({
    agentClass: 'setness-node22-14-disposable-ephemeral',
    nodeVersion: '22.14.0',
    npmVersion: '10.9.2',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci']),
      Object.freeze(['npm', 'run', 'maintenance']),
    ]),
  }),
  'node24-lint-typescript-test-v1': Object.freeze({
    agentClass: 'setness-node24-ephemeral',
    nodeVersion: '24.21.0',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci']),
      Object.freeze(['npm', 'run', 'lint']),
      Object.freeze(['node_modules/.bin/tsc', '--noEmit']),
      Object.freeze(['npm', 'test']),
    ]),
  }),
  'node24-game-platform-sdk-v1': Object.freeze({
    agentClass: 'setness-node24-ephemeral',
    nodeVersion: '24.21.0',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci']),
      Object.freeze(['npm', 'run', 'verify']),
      Object.freeze(['npm', 'run', 'verify:bundle']),
    ]),
  }),
  'node24-game-planetary-survey-v1': Object.freeze({
    agentClass: 'setness-node24-ephemeral',
    nodeVersion: '24.21.0',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci']),
      Object.freeze(['npm', 'run', 'verify']),
    ]),
  }),
  'node24-game-fraction-match-full-ci-v1': Object.freeze({
    agentClass: 'secondary-node24-playwright-ephemeral',
    nodeVersion: '24.21.0',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci']),
      Object.freeze(['npm', 'run', 'typecheck']),
      Object.freeze(['npm', 'run', 'lint']),
      Object.freeze(['npm', 'run', 'test:coverage']),
      Object.freeze(['npm', 'run', 'check:architecture']),
      Object.freeze(['npm', 'run', 'build']),
      Object.freeze(['npm', 'run', 'check:privacy']),
      Object.freeze(['npm', 'run', 'test:e2e:run']),
      Object.freeze(['npm', 'run', 'test:host:run']),
    ]),
  }),
  'node24-curiouspathway-pilot-v1': Object.freeze({
    agentClass: 'secondary-node24-playwright-ephemeral',
    nodeVersion: '24.21.0',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci', '--no-audit', '--no-fund']),
      Object.freeze(['npm', 'run', 'typecheck']),
      Object.freeze(['npm', 'run', 'lint']),
      Object.freeze(['npm', 'run', 'test:math-escape-preservation']),
      Object.freeze(['npm', 'test']),
      Object.freeze(['npm', 'run', 'build']),
      Object.freeze(['npm', 'run', 'build:e2e']),
      Object.freeze([
        'npm', 'run', 'test:e2e:run', '--', '--forbid-only',
        '--output=test-results/pilot-core',
        'tests/wave1/e2e/foundation.spec.ts',
        'tests/wave1/e2e/cloudflareFoundation.spec.ts',
        'tests/wave2/e2e/pilotEntry.spec.ts',
        'tests/wave3/e2e/pilotAssessment.spec.ts',
        'tests/wave4/e2e/pilotLearning.spec.ts',
        'tests/wave5/e2e/pilotJourney.spec.ts',
      ]),
      Object.freeze([
        'npm', 'run', 'test:e2e:run', '--', '--forbid-only',
        '--output=test-results/pilot-no-games',
        'tests/wave6/e2e/noGames.spec.ts',
      ]),
      Object.freeze([
        'npm', 'run', 'test:e2e:run', '--', '--forbid-only',
        '--output=test-results/pilot-a11y',
        'tests/wave2/e2e/mobileLayout.spec.ts',
        'tests/wave7/e2e/qualification.spec.ts',
      ]),
    ]),
  }),
  'python312-test-platform-v1': Object.freeze({
    agentClass: 'setness-python312-ephemeral',
    pythonVersion: '3.12.14',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['python', '-m', 'pip', 'install', '-e', '.[dev]']),
      Object.freeze(['python', '-m', 'test_platform.verify']),
    ]),
  }),
  'python312-playtest-lab-v1': Object.freeze({
    agentClass: 'setness-python312-ephemeral',
    pythonVersion: '3.12.14',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['python', '-m', 'pip', 'install', '--upgrade', 'pip']),
      Object.freeze(['python', '-m', 'pip', 'install', '.[test]']),
      Object.freeze(['mkdir', '-p', '.frameworks']),
      Object.freeze([
        'git', 'clone', '--filter=blob:none',
        'https://github.com/gameworld-project/GameWorld.git',
        '.frameworks/gameworld-upstream',
      ]),
      Object.freeze([
        'git', '-C', '.frameworks/gameworld-upstream',
        'checkout', '--detach', '3c26bdab436800fd61ef40543b64ca40d12c7e4a',
      ]),
      Object.freeze(['python', '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py', '-v']),
    ]),
  }),
  'python312-cloudflare-api-uv-v1': Object.freeze({
    agentClass: 'setness-python312-ephemeral',
    pythonVersion: '3.12.14',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['python', '-m', 'pip', 'install', '--disable-pip-version-check', 'uv==0.11.17']),
      Object.freeze(['uv', 'sync', '--locked', '--extra', 'dev']),
      Object.freeze(['uv', 'run', 'python', 'scripts/verify.py']),
      Object.freeze(['uv', 'run', 'cloudflare-api', 'doctor', '--json']),
    ]),
  }),
  'python312-portfolio-graph-uv-v1': Object.freeze({
    agentClass: 'setness-python312-ephemeral',
    pythonVersion: '3.12.14',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['python', '-m', 'pip', 'install', '--disable-pip-version-check', 'uv==0.11.17']),
      Object.freeze(['uv', 'sync', '--locked']),
      Object.freeze(['uv', 'run', '--locked', 'python', 'scripts/verify.py']),
      Object.freeze(['uv', 'run', '--locked', 'portfolio', '--help']),
      Object.freeze(['uv', 'run', '--locked', 'portfolio', '--version']),
      Object.freeze(['uv', 'run', '--locked', 'portfolio', 'doctor', '--json']),
    ]),
  }),
  'python312-blender-api-v1': Object.freeze({
    agentClass: 'setness-python312-ephemeral',
    pythonVersion: '3.12.14',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['python', '-m', 'pip', 'install', '--require-hashes', '-r', 'requirements-lock-linux-py312.txt']),
      Object.freeze(['python', '-m', 'pip', 'install', '--no-deps', '--no-build-isolation', '-e', '.']),
      Object.freeze(['python', '-m', 'ruff', 'check', '.']),
      Object.freeze(['python', '-m', 'mypy', 'src']),
      Object.freeze(['python', '-m', 'pytest', '-q']),
      Object.freeze([
        'python', '-m', 'pytest', '-q',
        'tests/test_batch_recovery.py', 'tests/test_batch_pipeline.py',
        'tests/test_batch.py', 'tests/test_runtime.py', 'tests/test_qualification.py',
        'tests/test_qualification_identity.py',
      ]),
    ]),
  }),
  'python312-fmod-api-v1': Object.freeze({
    agentClass: 'setness-python312-ephemeral',
    pythonVersion: '3.12.14',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['python', '-m', 'pip', 'install', '.[dev]']),
      Object.freeze(['python', 'scripts/generate_scripting_api.py', '--check']),
      Object.freeze(['python', '-m', 'ruff', 'check', '.']),
      Object.freeze(['python', 'scripts/scan_secrets.py']),
      Object.freeze(['python', '-m', 'mypy', 'src']),
      Object.freeze(['python', '-m', 'pytest', '-q']),
      Object.freeze(['python', '-m', 'build']),
    ]),
  }),
  'python312-game-maker-v1': Object.freeze({
    agentClass: 'setness-game-maker-python-matrix-ephemeral',
    pythonVersion: '3.12.14',
    additionalPythonVersion: '3.11.17',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['python3.11', '-m', 'pip', 'install', '--upgrade', 'pip']),
      Object.freeze(['python3.11', '-m', 'pip', 'install', '-e', '.[dev]']),
      Object.freeze(['python3.11', '-m', 'ruff', 'check', '.']),
      Object.freeze(['python3.11', '-m', 'mypy', 'src']),
      Object.freeze(['python3.11', '-m', 'pytest', '-q']),
      Object.freeze(['python3.11', '-m', 'game_maker', '--version']),
      Object.freeze(['python3.11', '-m', 'game_maker', '--help']),
      Object.freeze(['python3.11', '-m', 'game_maker', 'doctor']),
      Object.freeze(['python3.11', '-m', 'game_maker', 'status']),
      Object.freeze([
        'python3.11', '-c',
        "import subprocess, sys; result = subprocess.run(['git', 'status', '--porcelain'], check=True, capture_output=True, text=True); print(result.stdout, end=''); sys.exit(1 if result.stdout else 0)",
      ]),
      Object.freeze(['python', '-m', 'pip', 'install', '--upgrade', 'pip']),
      Object.freeze(['python', '-m', 'pip', 'install', '-e', '.[dev]']),
      Object.freeze(['python', '-m', 'ruff', 'check', '.']),
      Object.freeze(['python', '-m', 'mypy', 'src']),
      Object.freeze(['python', '-m', 'pytest', '-q']),
      Object.freeze(['python', '-m', 'game_maker', '--version']),
      Object.freeze(['python', '-m', 'game_maker', '--help']),
      Object.freeze(['python', '-m', 'game_maker', 'doctor']),
      Object.freeze(['python', '-m', 'game_maker', 'status']),
      Object.freeze([
        'python', '-c',
        "import subprocess, sys; result = subprocess.run(['git', 'status', '--porcelain'], check=True, capture_output=True, text=True); print(result.stdout, end=''); sys.exit(1 if result.stdout else 0)",
      ]),
    ]),
  }),
  'python312-context-file-maker-v1': Object.freeze({
    agentClass: 'setness-python312-ephemeral',
    pythonVersion: '3.12.14',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['python', '-m', 'pip', 'install', 'pytest', 'jsonschema']),
      Object.freeze(['python', '-m', 'pytest', '-q']),
      Object.freeze(['python', 'scripts/validate.py', '--strict']),
    ]),
  }),
  'python312-cpa-ai-pack-v1': Object.freeze({
    agentClass: 'setness-python312-ephemeral',
    pythonVersion: '3.12.14',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['python', '-m', 'pip', 'install', 'pytest']),
      Object.freeze(['python', 'scripts/check_release.py']),
      Object.freeze(['python', '-m', 'pytest', '-q']),
      Object.freeze([
        'python', '-c',
        "import hashlib, json; from pathlib import Path; expected_raw = '2dd103d7624c1021d19f04a8b4a64fae38c2e26935cba425f88fe1a9d0a2af2c'; expected_content = 'edac0d21deb04df402e2c8715eaacfe9d4f60aaa0e31be242fd540619b157de5'; zip_path = Path('dist/ai-skills-agent-starter-pack-1.0.0.zip'); raw = hashlib.sha256(zip_path.read_bytes()).hexdigest(); recorded = json.loads(Path('RELEASE.json').read_text(encoding='utf-8'))['checksum_sha256']; print(f'raw_sha256={raw}'); print(f'release_content_checksum={recorded}'); assert raw == expected_raw; assert recorded == expected_content",
      ]),
    ]),
  }),
});

// Only implementations explicitly admitted here may be polled automatically.
// Adding an implementation requires a reviewed trusted runtime and profile
// contract; catalog data cannot expand this set.
// Routine dispatch remains a separate explicit opt-in from catalog shadow
// status. A pair makes only that fixed implementation/repository eligible for
// owner-authored PR polling; it does not make the profile authoritative. Keep
// each implementation bound to its repository so catalog data cannot cross-pair
// two otherwise approved entries.
export const ROUTINE_DISPATCH_PROFILE_PAIRS = Object.freeze([
  Object.freeze({ implementationId: 'node22-github-api-foundation-v1', repository: 'setnessconsulting/project-github-api' }),
  Object.freeze({ implementationId: 'node22-verify-clean-checkout-v1', repository: 'setnessconsulting/project-jira-api' }),
  Object.freeze({ implementationId: 'python312-test-platform-v1', repository: 'setnessconsulting/project-test-platform' }),
  Object.freeze({ implementationId: 'python312-blender-api-v1', repository: 'setnessconsulting/project-blender-api' }),
  Object.freeze({ implementationId: 'python312-cloudflare-api-uv-v1', repository: 'setnessconsulting/project-cloudflare-api' }),
  Object.freeze({ implementationId: 'python312-fmod-api-v1', repository: 'setnessconsulting/project-fmod-api' }),
  Object.freeze({ implementationId: 'python312-game-maker-v1', repository: 'setnessconsulting/project-game-maker' }),
  Object.freeze({ implementationId: 'node24-game-platform-sdk-v1', repository: 'setnessconsulting/project-game-platform-sdk' }),
  Object.freeze({ implementationId: 'node24-game-planetary-survey-v1', repository: 'setnessconsulting/Game-Planetary-Survey' }),
  Object.freeze({ implementationId: 'node24-game-fraction-match-full-ci-v1', repository: 'setnessconsulting/game-fraction-match' }),
  Object.freeze({ implementationId: 'node24-curiouspathway-pilot-v1', repository: 'setnessconsulting/curiouspathway' }),
  Object.freeze({ implementationId: 'python312-portfolio-graph-uv-v1', repository: 'setnessconsulting/project-portfolio-graph' }),
  Object.freeze({ implementationId: 'node2214-vercel-api-gitleaks-v1', repository: 'setnessconsulting/project-vercel-api' }),
  Object.freeze({ implementationId: 'node2214-unity-api-maintenance-v1', repository: 'setnessconsulting/project-unity-api' }),
  Object.freeze({ implementationId: 'jenkins-repository-contract', repository: 'setnessconsulting/project-jenkins' }),
  Object.freeze({ implementationId: 'setness-web-ci-node22-v1', repository: 'setnessconsulting/project-setness-consulting' }),
]);

// Some newly reviewed implementations are repository-specific even for manual
// dispatch. Keep that binding in trusted code so catalog data cannot cross-pair
// their command plan with another repository.
const FIXED_IMPLEMENTATION_REPOSITORIES = Object.freeze({
  'node2214-unity-api-maintenance-v1': 'setnessconsulting/project-unity-api',
  'node24-game-fraction-match-full-ci-v1': 'setnessconsulting/game-fraction-match',
  'python312-game-maker-v1': 'setnessconsulting/project-game-maker',
});

const FIXED_IMPLEMENTATION_PROFILE_IDS = Object.freeze({
  'node24-game-fraction-match-full-ci-v1': 'game-fraction-match-node24-full-ci',
  'python312-game-maker-v1': 'project-game-maker-python312',
});

// A catalog can select only the centrally reviewed behavior matrix for its
// implementation. These counts mirror the private profile matrix: four
// standard cases, five Game AI cases, and six Vercel API cases. The count is
// not itself evidence; every distinct case still needs exact-SHA evidence.
const QUALIFICATION_CASES_BY_IMPLEMENTATION = Object.freeze({
  'node22-github-api-foundation-v1': 4,
  'setness-web-ci-node22-v1': 4,
  'jenkins-repository-contract': 4,
  'setness-repository-pilot': 4,
  'curiouspathway-pilot': 4,
  'node22-foundation-v1': 4,
  'node22-verify-clean-checkout-v1': 4,
  'node2214-vercel-api-gitleaks-v1': 6,
  'node2214-unity-api-maintenance-v1': 4,
  'node24-lint-typescript-test-v1': 4,
  'node24-game-platform-sdk-v1': 4,
  'node24-game-planetary-survey-v1': 4,
  'node24-game-fraction-match-full-ci-v1': 4,
  'node24-curiouspathway-pilot-v1': 4,
  'python312-test-platform-v1': 4,
  'python312-playtest-lab-v1': 5,
  'python312-cloudflare-api-uv-v1': 4,
  'python312-portfolio-graph-uv-v1': 4,
  'python312-blender-api-v1': 4,
  'python312-fmod-api-v1': 4,
  'python312-game-maker-v1': 4,
  'python312-context-file-maker-v1': 4,
  'python312-cpa-ai-pack-v1': 4,
});

export const ROUTINE_DISPATCH_IMPLEMENTATIONS = Object.freeze(
  ROUTINE_DISPATCH_PROFILE_PAIRS.map(({ implementationId }) => implementationId),
);

export const ROUTINE_DISPATCH_REPOSITORIES = Object.freeze(
  ROUTINE_DISPATCH_PROFILE_PAIRS.map(({ repository }) => repository),
);

export class ProfileRejection extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'ProfileRejection';
    this.code = code;
  }
}

function reject(code, message) {
  throw new ProfileRejection(code, message);
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, allowed, required, label) {
  if (!isRecord(value)) reject('malformed-catalog', `${label} must be an object`);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) reject('unexpected-field', `${label} contains unsupported field ${key}`);
  }
  for (const key of required) {
    if (!Object.hasOwn(value, key)) reject('missing-field', `${label} is missing ${key}`);
  }
}

function validId(value) {
  return typeof value === 'string' && /^[a-z0-9][a-z0-9-]{1,63}$/.test(value);
}

function validRepository(value) {
  return typeof value === 'string'
    && /^setnessconsulting\/[A-Za-z0-9._-]{1,100}$/.test(value);
}

function validCheckName(value) {
  return typeof value === 'string'
    && /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,99}$/.test(value);
}

function validateQualification(qualification, profileId, implementationId) {
  exactKeys(
    qualification,
    QUALIFICATION_KEYS,
    ['requiredExactShaCases', 'qualifiedExactShaCases', 'state'],
    `profile ${profileId} qualification`,
  );
  const { requiredExactShaCases, qualifiedExactShaCases, state, evidenceReference } = qualification;
  if (!Number.isInteger(requiredExactShaCases) || requiredExactShaCases < 0
      || !Number.isInteger(qualifiedExactShaCases) || qualifiedExactShaCases < 0
      || qualifiedExactShaCases > requiredExactShaCases
      || !QUALIFICATION_STATES.has(state)) {
    reject('invalid-qualification', `profile ${profileId} has invalid qualification evidence`);
  }
  const expectedCases = QUALIFICATION_CASES_BY_IMPLEMENTATION[implementationId];
  if (expectedCases !== undefined && requiredExactShaCases !== expectedCases) {
    reject(
      'qualification-matrix-mismatch',
      `profile ${profileId} must use its centrally reviewed ${expectedCases}-case matrix`,
    );
  }
  if (state === 'passed' && (requiredExactShaCases < 1
      || qualifiedExactShaCases < requiredExactShaCases
      || typeof evidenceReference !== 'string' || !evidenceReference.trim())) {
    reject('qualification-overclaim', `profile ${profileId} claims a pass without complete evidence`);
  }
}

function validateForkQualification(qualification, profileId) {
  exactKeys(qualification, FORK_QUALIFICATION_KEYS, ['state'], `profile ${profileId} fork qualification`);
  if (!QUALIFICATION_STATES.has(qualification.state)) {
    reject('invalid-fork-qualification', `profile ${profileId} has an invalid fork qualification state`);
  }
  if (qualification.state === 'passed'
      && (typeof qualification.evidenceReference !== 'string' || !qualification.evidenceReference.trim())) {
    reject('fork-qualification-overclaim', `profile ${profileId} claims a fork pass without evidence`);
  }
}

export function validateProfileCatalog(catalog) {
  exactKeys(catalog, CATALOG_KEYS,
    ['schemaVersion', 'approvedImplementations', 'profiles', 'controlPlane'], 'catalog');
  if (catalog.schemaVersion !== 1 || !Array.isArray(catalog.approvedImplementations)
      || !Array.isArray(catalog.profiles)) {
    reject('malformed-catalog', 'catalog version, implementation allowlist, or profiles are invalid');
  }
  if (new Set(catalog.approvedImplementations).size !== catalog.approvedImplementations.length
      || catalog.approvedImplementations.some((id) => !validId(id))) {
    reject('invalid-implementation-allowlist', 'catalog implementation allowlist must contain unique valid IDs');
  }

  exactKeys(catalog.controlPlane, CONTROL_PLANE_KEYS,
    ['repository', 'validationProfileId', 'status'], 'catalog control plane');
  if (!validRepository(catalog.controlPlane.repository)
      || !validId(catalog.controlPlane.validationProfileId)
      || !['planned', 'active', 'blocked'].includes(catalog.controlPlane.status)) {
    reject('invalid-control-plane', 'catalog control-plane metadata is invalid');
  }

  const profileIds = new Set();
  const repositoryOwners = new Map();
  for (const profile of catalog.profiles) {
    exactKeys(profile, PROFILE_KEYS,
      ['id', 'status', 'repositories', 'checkNames', 'qualification'], 'profile');
    if (!validId(profile.id) || profileIds.has(profile.id)) {
      reject('invalid-profile-id', 'profile IDs must be valid and unique');
    }
    profileIds.add(profile.id);
    if (!PROFILE_STATUSES.has(profile.status) || !Array.isArray(profile.repositories)
        || profile.repositories.length === 0 || profile.repositories.some((repo) => !validRepository(repo))
        || new Set(profile.repositories.map((repository) => repository.toLowerCase())).size
          !== profile.repositories.length
        || !Array.isArray(profile.checkNames)
        || profile.checkNames.some((name) => !validCheckName(name))
        || new Set(profile.checkNames).size !== profile.checkNames.length) {
      reject('invalid-profile', `profile ${profile.id} has invalid status, repository, or check metadata`);
    }
    if (Object.hasOwn(profile, 'requiredNodeVersion')
        && (typeof profile.requiredNodeVersion !== 'string'
          || !/^\d+\.\d+\.\d+$/.test(profile.requiredNodeVersion))) {
      reject('invalid-toolchain', `profile ${profile.id} has an invalid required Node.js version`);
    }
    if (Object.hasOwn(profile, 'requiredPythonVersion')
        && (typeof profile.requiredPythonVersion !== 'string'
          || !/^\d+\.\d+\.\d+$/.test(profile.requiredPythonVersion))) {
      reject('invalid-toolchain', `profile ${profile.id} has an invalid required Python version`);
    }
    validateQualification(profile.qualification, profile.id, profile.implementationId);

    if (profile.status === 'unmapped') {
      if (Object.hasOwn(profile, 'implementationId') || Object.hasOwn(profile, 'forkSandboxQualification')
          || profile.checkNames.length !== 0
          || profile.qualification.requiredExactShaCases !== 0
          || profile.qualification.qualifiedExactShaCases !== 0
          || profile.qualification.state !== 'not-started') {
        reject('unmapped-profile-executable', `unmapped profile ${profile.id} must not select executable behavior`);
      }
    } else {
      if (!validId(profile.implementationId)
          || !catalog.approvedImplementations.includes(profile.implementationId)
          || profile.qualification.requiredExactShaCases < 1) {
        reject('unapproved-profile', `profile ${profile.id} must select an approved implementation and require exact-SHA evidence`);
      }
      const fixedRepository = FIXED_IMPLEMENTATION_REPOSITORIES[profile.implementationId];
      if (fixedRepository !== undefined
          && (profile.repositories.length !== 1
            || profile.repositories[0].toLowerCase() !== fixedRepository.toLowerCase())) {
        reject('implementation-repository-mismatch',
          `implementation ${profile.implementationId} is restricted to ${fixedRepository}`);
      }
      const fixedProfileId = FIXED_IMPLEMENTATION_PROFILE_IDS[profile.implementationId];
      if (fixedProfileId !== undefined && profile.id !== fixedProfileId) {
        reject('implementation-profile-mismatch',
          `implementation ${profile.implementationId} is restricted to profile ${fixedProfileId}`);
      }
    }
    if (profile.status === 'qualified'
        && (profile.qualification.state !== 'passed'
          || profile.qualification.qualifiedExactShaCases < profile.qualification.requiredExactShaCases)) {
      reject('qualification-overclaim', `profile ${profile.id} cannot be qualified without all exact-SHA cases`);
    }
    if (Object.hasOwn(profile, 'forkSandboxQualification')) {
      validateForkQualification(profile.forkSandboxQualification, profile.id);
    }
    for (const repository of profile.repositories) {
      const normalizedRepository = repository.toLowerCase();
      if (repositoryOwners.has(normalizedRepository)) {
        reject('duplicate-repository-profile', `repository ${repository} is assigned to multiple profiles`);
      }
      repositoryOwners.set(normalizedRepository, profile.id);
    }
  }

  return Object.freeze({
    profileCount: profileIds.size,
    implementationCount: catalog.approvedImplementations.length,
  });
}

function resolveShadowExecution(catalog, profileId, headSha) {
  validateProfileCatalog(catalog);
  if (!validId(profileId)) reject('invalid-profile-id', 'profile ID is invalid');
  if (typeof headSha !== 'string' || !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i.test(headSha)) {
    reject('invalid-head-sha', 'target must be a full Git commit SHA');
  }

  const profile = catalog.profiles.find((candidate) => candidate.id === profileId);
  if (!profile) reject('unknown-profile', 'profile is not present in the private catalog');
  if (!['shadow', 'qualified'].includes(profile.status)) {
    reject('profile-not-shadow', 'only an explicitly shadow or qualified profile may execute');
  }
  if (profile.repositories.length !== 1) reject('ambiguous-profile', 'an executable profile must identify exactly one repository');
  const implementation = IMPLEMENTATIONS[profile.implementationId];
  if (!implementation) reject('implementation-not-installed', 'no centrally trusted adapter is installed for this profile');
  const expectedCases = QUALIFICATION_CASES_BY_IMPLEMENTATION[profile.implementationId];
  if (expectedCases === undefined || profile.qualification.requiredExactShaCases !== expectedCases) {
    reject('qualification-matrix-mismatch', `profile ${profile.id} does not match its centrally reviewed qualification matrix`);
  }
  if (!profile.checkNames.includes(implementation.requiredCheck)) {
    reject('required-check-missing', 'profile does not declare the centrally required gate');
  }
  if (implementation.nodeVersion) {
    if (profile.requiredNodeVersion !== implementation.nodeVersion
        || Object.hasOwn(profile, 'requiredPythonVersion')) {
      reject('runtime-mismatch', 'profile Node.js version does not match the centrally pinned agent runtime');
    }
  } else if (implementation.pythonVersion) {
    if (profile.requiredPythonVersion !== implementation.pythonVersion
        || Object.hasOwn(profile, 'requiredNodeVersion')) {
      reject('runtime-mismatch', 'profile Python version does not match the centrally pinned agent runtime');
    }
  } else {
    reject('implementation-runtime-missing', 'central implementation has no pinned runtime');
  }

  return Object.freeze({
    profileId: profile.id,
    repository: profile.repositories[0],
    headSha: headSha.toLowerCase(),
    requiredCheck: implementation.requiredCheck,
    agentClass: implementation.agentClass,
    ...(implementation.nodeVersion ? { nodeVersion: implementation.nodeVersion } : {}),
    ...(implementation.pythonVersion ? { pythonVersion: implementation.pythonVersion } : {}),
    ...(implementation.additionalPythonVersion ? { additionalPythonVersion: implementation.additionalPythonVersion } : {}),
    ...(implementation.npmVersion ? { npmVersion: implementation.npmVersion } : {}),
    commands: Object.freeze(implementation.commands.map((argv) => Object.freeze([...argv]))),
  });
}

export function verifyPullRequestHead(pr, { repository, pullRequestNumber, headSha, allowedAuthors }) {
  if (!validRepository(repository) || !Number.isInteger(pullRequestNumber) || pullRequestNumber < 1
      || typeof headSha !== 'string' || !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i.test(headSha)
      || !Array.isArray(allowedAuthors) || allowedAuthors.length === 0) {
    reject('invalid-pr-request', 'repository, PR number, head SHA, and trusted author policy are required');
  }
  const canonicalSha = headSha.toLowerCase();
  const currentHeadSha = pr?.head?.sha;
  const headRepository = pr?.head?.repo?.full_name;
  const baseRepository = pr?.base?.repo?.full_name;
  const expectedRepository = repository.toLowerCase();
  if (!isRecord(pr) || pr.number !== pullRequestNumber || pr.state !== 'open'
      || pr.draft !== false
      || typeof currentHeadSha !== 'string'
      || !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i.test(currentHeadSha)
      || currentHeadSha.toLowerCase() !== canonicalSha
      || typeof headRepository !== 'string'
      || headRepository.toLowerCase() !== expectedRepository
      || typeof baseRepository !== 'string'
      || baseRepository.toLowerCase() !== expectedRepository) {
    reject('stale-or-untrusted-pr', 'PR must be open, same-repository, and point to the requested exact head SHA');
  }
  const author = pr.user?.login;
  if (typeof author !== 'string' || !allowedAuthors.some((allowed) =>
    typeof allowed === 'string' && allowed.toLowerCase() === author.toLowerCase())) {
    reject('author-not-allowed', 'PR author is outside the trusted shadow allowlist');
  }
  return Object.freeze({ repository, pullRequestNumber, headSha: canonicalSha, author });
}

// This is the only supported PR execution entry point. It binds the trusted
// Branch Source metadata and exact SHA to the profile before exposing the
// centrally-owned command vectors to a caller.
export function resolveAuthorizedShadowPullRequest(
  catalog,
  profileId,
  pr,
  { repository, pullRequestNumber, headSha, allowedAuthors },
) {
  const verified = verifyPullRequestHead(pr, {
    repository,
    pullRequestNumber,
    headSha,
    allowedAuthors,
  });
  const execution = resolveShadowExecution(catalog, profileId, verified.headSha);
  if (execution.repository.toLowerCase() !== verified.repository.toLowerCase()) {
    reject('profile-repository-mismatch', 'verified PR repository does not match the shadow profile');
  }

  return Object.freeze({
    ...execution,
    pullRequestNumber: verified.pullRequestNumber,
    author: verified.author,
  });
}

// Portfolio dispatchers should bind the profile from the repository identity,
// not accept an independently supplied profile ID that could drift from the
// SCM source being evaluated.
export function resolveAuthorizedShadowPullRequestForRepository(catalog, pr, request) {
  validateProfileCatalog(catalog);
  const repository = request?.repository;
  if (!validRepository(repository)) {
    reject('invalid-pr-request', 'a valid repository identity is required to select a profile');
  }

  const profile = catalog.profiles.find((candidate) => candidate.repositories.some((candidateRepository) =>
    candidateRepository.toLowerCase() === repository.toLowerCase()));
  if (!profile) {
    reject('unknown-profile', 'repository is not mapped to a private catalog profile');
  }

  return resolveAuthorizedShadowPullRequest(catalog, profile.id, pr, request);
}

function pollStateKey(repository, pullRequestNumber) {
  return `${repository.toLowerCase()}#${pullRequestNumber}`;
}

const POLL_RETRY_AFTER_MS = 15 * 60 * 1000;
const POLL_MAX_ATTEMPTS = 3;

function validatePollState(previousState) {
  if (!Array.isArray(previousState) || previousState.length > 20000) {
    reject('invalid-poll-state', 'poll state must be a bounded array');
  }
  const state = new Map();
  for (const entry of previousState) {
    exactKeys(entry, new Set(['repository', 'pullRequestNumber', 'headSha', 'attempt', 'dispatchedAtEpochMs', 'status', 'dispatchId']),
      ['repository', 'pullRequestNumber', 'headSha', 'attempt', 'dispatchedAtEpochMs', 'status'], 'poll state entry');
    if (!validRepository(entry.repository)
        || !Number.isInteger(entry.pullRequestNumber) || entry.pullRequestNumber < 1
        || typeof entry.headSha !== 'string' || !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i.test(entry.headSha)
        || !Number.isInteger(entry.attempt) || entry.attempt < 1 || entry.attempt > POLL_MAX_ATTEMPTS
        || !Number.isSafeInteger(entry.dispatchedAtEpochMs) || entry.dispatchedAtEpochMs < 0
        || !['pending', 'completed', 'stalled'].includes(entry.status)
        || (Object.hasOwn(entry, 'dispatchId')
          && (typeof entry.dispatchId !== 'string'
            || !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(entry.dispatchId)))) {
      reject('invalid-poll-state', 'poll state entry is invalid');
    }
    const key = pollStateKey(entry.repository, entry.pullRequestNumber);
    if (state.has(key)) reject('invalid-poll-state', 'poll state contains a duplicate PR');
    state.set(key, Object.freeze({
      repository: entry.repository,
      pullRequestNumber: entry.pullRequestNumber,
      headSha: entry.headSha.toLowerCase(),
      attempt: entry.attempt,
      dispatchedAtEpochMs: entry.dispatchedAtEpochMs,
      status: entry.status,
      ...(Object.hasOwn(entry, 'dispatchId') ? { dispatchId: entry.dispatchId.toLowerCase() } : {}),
    }));
  }
  return state;
}

function validatePollObservations(checkObservations) {
  if (!Array.isArray(checkObservations) || checkObservations.length > 20000) {
    reject('invalid-poll-input', 'check observations must be a bounded array');
  }
  const observations = new Map();
  for (const observation of checkObservations) {
    exactKeys(observation, new Set(['repository', 'pullRequestNumber', 'headSha', 'status']),
      ['repository', 'pullRequestNumber', 'headSha', 'status'], 'poll check observation');
    if (!validRepository(observation.repository)
        || !Number.isInteger(observation.pullRequestNumber) || observation.pullRequestNumber < 1
        || typeof observation.headSha !== 'string' || !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i.test(observation.headSha)
        || !['missing', 'in_progress', 'orphaned', 'untracked', 'completed'].includes(observation.status)) {
      reject('invalid-poll-input', 'poll check observation is invalid');
    }
    const key = pollStateKey(observation.repository, observation.pullRequestNumber);
    if (observations.has(key)) reject('invalid-poll-input', 'poll input contains duplicate check observations');
    observations.set(key, Object.freeze({ ...observation, headSha: observation.headSha.toLowerCase() }));
  }
  return observations;
}

export function listRoutinePullRequestPollRepositories(catalog) {
  validateProfileCatalog(catalog);
  if (catalog.controlPlane.status !== 'active') return Object.freeze([]);
  return Object.freeze(catalog.profiles
    .filter((profile) => ['shadow', 'qualified'].includes(profile.status)
      && profile.repositories.length === 1
      && ROUTINE_DISPATCH_PROFILE_PAIRS.some((pair) =>
        pair.implementationId === profile.implementationId
        && pair.repository.toLowerCase() === profile.repositories[0].toLowerCase()))
    .flatMap((profile) => {
      if (profile.repositories.length !== 1) {
        reject('ambiguous-profile', 'a polled profile must identify exactly one repository');
      }
      return [profile.repositories[0]];
    })
    .sort((left, right) => left.localeCompare(right)));
}

// Pure controller-side planning for the scheduled PR poller. It never runs
// repository code; only exact-SHA requests accepted by the existing trusted
// PR resolver are returned for the downstream centrally defined gate.
export function planRoutinePullRequestPoll(catalog, pullRequestsByRepository, previousState, checkObservations, nowEpochMs) {
  validateProfileCatalog(catalog);
  const prior = validatePollState(previousState);
  const observations = validatePollObservations(checkObservations);
  if (!Number.isSafeInteger(nowEpochMs) || nowEpochMs < 0) {
    reject('invalid-poll-input', 'poll time must be a non-negative safe integer');
  }
  if (catalog.controlPlane.status !== 'active') {
    return Object.freeze({ status: 'inactive', dispatches: Object.freeze([]), state: Object.freeze([...prior.values()]) });
  }

  const repositories = listRoutinePullRequestPollRepositories(catalog);
  if (!Array.isArray(pullRequestsByRepository)
      || pullRequestsByRepository.length !== repositories.length) {
    reject('invalid-poll-input', 'poll input must contain every and only approved repository');
  }
  const pullRequests = new Map();
  for (const record of pullRequestsByRepository) {
    exactKeys(record, new Set(['repository', 'pullRequests']), ['repository', 'pullRequests'], 'poll repository');
    if (!validRepository(record.repository) || !Array.isArray(record.pullRequests)
        || record.pullRequests.length > 1000) {
      reject('invalid-poll-input', 'poll repository identity or PR list is invalid');
    }
    const key = record.repository.toLowerCase();
    if (pullRequests.has(key)) reject('invalid-poll-input', 'poll input contains a duplicate repository');
    pullRequests.set(key, record);
  }
  if (repositories.some((repository) => !pullRequests.has(repository.toLowerCase()))) {
    reject('invalid-poll-input', 'poll input must contain every and only approved repository');
  }
  if ([...pullRequests.keys()].some((repository) => !repositories.some((item) => item.toLowerCase() === repository))) {
    reject('invalid-poll-input', 'poll input must contain every and only approved repository');
  }

  const profileByRepository = new Map();
  for (const profile of catalog.profiles) {
    if (!['shadow', 'qualified'].includes(profile.status)
        || !ROUTINE_DISPATCH_IMPLEMENTATIONS.includes(profile.implementationId)) continue;
    const repository = profile.repositories[0];
    profileByRepository.set(repository.toLowerCase(), profile);
  }

  const dispatchCandidates = [];
  // Rebuild only from current eligible open PRs so closed, draft, fork, denied,
  // and no-longer-enabled entries cannot remain permanently queued in state.
  const nextState = new Map();

  for (const repository of repositories) {
    const record = pullRequests.get(repository.toLowerCase());
    const profile = profileByRepository.get(repository.toLowerCase());
    const currentPullRequests = new Set();
    for (const pr of record.pullRequests) {
      if (!Number.isInteger(pr?.number) || pr.number < 1) {
        reject('invalid-poll-input', 'a polled PR is missing a valid number');
      }
      let execution;
      try {
        execution = resolveAuthorizedShadowPullRequestForRepository(catalog, pr, {
          repository,
          pullRequestNumber: pr.number,
          headSha: pr?.head?.sha,
          allowedAuthors: ['setnessconsulting'],
        });
      } catch (error) {
        if (error instanceof ProfileRejection
            && ['author-not-allowed', 'stale-or-untrusted-pr'].includes(error.code)) continue;
        throw error;
      }
      const key = pollStateKey(repository, execution.pullRequestNumber);
      if (currentPullRequests.has(key)) reject('invalid-poll-input', 'poll input contains a duplicate PR');
      currentPullRequests.add(key);
      const previous = prior.get(key);
      if (!previous || previous.headSha !== execution.headSha) {
        dispatchCandidates.push(Object.freeze({
          repository,
          pullRequestNumber: execution.pullRequestNumber,
          headSha: execution.headSha,
          profileId: profile.id,
          attempt: 1,
        }));
        continue;
      }

      if (previous.status === 'completed') {
        nextState.set(key, previous);
        continue;
      }

      const observation = observations.get(key);
      if (!observation || observation.headSha !== execution.headSha) {
        reject('invalid-poll-input', 'every pending PR must have a matching exact-SHA check observation');
      }
      if (observation.status === 'completed') {
        nextState.set(key, Object.freeze({ ...previous, status: 'completed' }));
      } else if (observation.status === 'in_progress') {
        nextState.set(key, previous.status === 'stalled'
          ? Object.freeze({ ...previous, status: 'pending' })
          : previous);
      } else if (observation.status === 'untracked') {
        // A check not linked to this trusted poller's gate build may belong to
        // another Jenkins job. Never overwrite or duplicate it; surface the
        // state for operator attention after the normal grace period.
        nextState.set(key, previous.status === 'stalled' || nowEpochMs - previous.dispatchedAtEpochMs < POLL_RETRY_AFTER_MS
          ? previous
          : Object.freeze({ ...previous, status: 'stalled' }));
      } else if (previous.status === 'stalled') {
        nextState.set(key, previous);
      } else if (nowEpochMs - previous.dispatchedAtEpochMs < POLL_RETRY_AFTER_MS) {
        nextState.set(key, previous);
      } else if (previous.attempt < POLL_MAX_ATTEMPTS) {
        dispatchCandidates.push(Object.freeze({
          repository,
          pullRequestNumber: execution.pullRequestNumber,
          headSha: execution.headSha,
          profileId: profile.id,
          attempt: previous.attempt + 1,
        }));
        // A retry candidate is not an attempt until the single downstream job
        // selected by this plan is actually queued. Preserve its last recorded
        // state while it waits behind other candidates.
        nextState.set(key, previous);
      } else {
        nextState.set(key, Object.freeze({ ...previous, status: 'stalled' }));
      }
    }
  }

  dispatchCandidates.sort((left, right) => left.repository.localeCompare(right.repository)
    || left.pullRequestNumber - right.pullRequestNumber);
  // The trusted Jenkins adapter queues exactly one downstream build per poll.
  // Persist an attempt only for that selected PR; other eligible PRs remain
  // candidates and are not penalized for not having been queued.
  const dispatches = dispatchCandidates.slice(0, 1);
  const selected = dispatches[0];
  if (selected) {
    const key = pollStateKey(selected.repository, selected.pullRequestNumber);
    nextState.set(key, Object.freeze({
      repository: selected.repository,
      pullRequestNumber: selected.pullRequestNumber,
      headSha: selected.headSha,
      attempt: selected.attempt,
      dispatchedAtEpochMs: nowEpochMs,
      status: 'pending',
    }));
  }
  return Object.freeze({
    status: 'ready',
    dispatches: Object.freeze(dispatches),
    state: Object.freeze([...nextState.values()].sort((left, right) =>
      pollStateKey(left.repository, left.pullRequestNumber).localeCompare(
        pollStateKey(right.repository, right.pullRequestNumber),
      ))),
  });
}
