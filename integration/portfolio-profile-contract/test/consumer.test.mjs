import assert from 'node:assert/strict';
import test from 'node:test';

import * as profileConsumer from '../src/consumer.mjs';

const {
  IMPLEMENTATIONS,
  ProfileRejection,
  ROUTINE_DISPATCH_IMPLEMENTATIONS,
  ROUTINE_DISPATCH_PROFILE_PAIRS,
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

test('resolves the project-jenkins self-check on the no-socket Node 22.23 agent', () => {
  const input = catalog();
  input.approvedImplementations.push('jenkins-repository-contract');
  input.profiles[0].implementationId = 'jenkins-repository-contract';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-web-ci-node22-ephemeral');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.equal(plan.nodeVersion, '22.23.3');
  assert.equal(Object.hasOwn(plan, 'npmVersion'), false);
  assert.deepEqual(plan.commands, [
    [
      'node', '--test',
      'integration/portfolio-profile-contract/test/consumer.test.mjs',
      'integration/portfolio-profile-contract/test/plan-poll-cli.test.mjs',
      'integration/portfolio-profile-contract/test/plan-poll.test.mjs',
      'integration/portfolio-profile-contract/test/resolve-pr.test.mjs',
    ],
    ['node', '--test', 'integration/test-platform-contract/test/adapter.test.mjs'],
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

test('resolves the Game Platform SDK workflow on pinned Node 24', () => {
  const input = catalog();
  input.approvedImplementations.push('node24-game-platform-sdk-v1');
  input.profiles[0].implementationId = 'node24-game-platform-sdk-v1';
  input.profiles[0].requiredNodeVersion = '24.21.0';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-node24-ephemeral');
  assert.equal(plan.nodeVersion, '24.21.0');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.deepEqual(plan.commands, [
    ['npm', 'ci'],
    ['npm', 'run', 'verify'],
    ['npm', 'run', 'verify:bundle'],
  ]);
  assert.equal(ROUTINE_DISPATCH_IMPLEMENTATIONS.includes('node24-game-platform-sdk-v1'), true);

  input.profiles[0].requiredNodeVersion = '24.21.1';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

test('resolves the Planetary Survey Node 24 verify lane for its exact repository', () => {
  const input = catalog();
  input.approvedImplementations.push('node24-game-planetary-survey-v1');
  input.profiles[0].id = 'game-planetary-survey-node24';
  input.profiles[0].implementationId = 'node24-game-planetary-survey-v1';
  input.profiles[0].repositories = ['setnessconsulting/Game-Planetary-Survey'];
  input.profiles[0].requiredNodeVersion = '24.21.0';
  const resolvePlanetarySurvey = () => resolve(input, {
    profileId: 'game-planetary-survey-node24',
    prOverrides: {
      head: { sha, repo: { full_name: 'setnessconsulting/Game-Planetary-Survey' } },
      base: { repo: { full_name: 'setnessconsulting/Game-Planetary-Survey' } },
    },
    repository: 'setnessconsulting/Game-Planetary-Survey',
  });

  const plan = resolvePlanetarySurvey();
  assert.equal(plan.agentClass, 'setness-node24-ephemeral');
  assert.equal(plan.nodeVersion, '24.21.0');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.deepEqual(plan.commands, [
    ['npm', 'ci'],
    ['npm', 'run', 'verify'],
  ]);
  assert.equal(ROUTINE_DISPATCH_IMPLEMENTATIONS.includes('node24-game-planetary-survey-v1'), true);
  assert.equal(ROUTINE_DISPATCH_PROFILE_PAIRS.some(({ implementationId, repository }) =>
    implementationId === 'node24-game-planetary-survey-v1'
      && repository === 'setnessconsulting/Game-Planetary-Survey'), true);

  input.profiles[0].requiredNodeVersion = '24.21.1';
  rejectsCode(() => resolvePlanetarySurvey(), 'runtime-mismatch');
});

test('resolves CuriousPathway Node 24 and three centrally selected Playwright suites', () => {
  const input = catalog();
  input.approvedImplementations.push('node24-curiouspathway-pilot-v1');
  input.profiles[0].implementationId = 'node24-curiouspathway-pilot-v1';
  input.profiles[0].requiredNodeVersion = '24.21.0';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'secondary-node24-playwright-ephemeral');
  assert.equal(plan.nodeVersion, '24.21.0');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.deepEqual(plan.commands, [
    ['npm', 'ci', '--no-audit', '--no-fund'],
    ['npm', 'run', 'typecheck'],
    ['npm', 'run', 'lint'],
    ['npm', 'run', 'test:math-escape-preservation'],
    ['npm', 'test'],
    ['npm', 'run', 'build'],
    ['npm', 'run', 'build:e2e'],
    [
      'npm', 'run', 'test:e2e:run', '--', '--forbid-only',
      '--output=test-results/pilot-core',
      'tests/wave1/e2e/foundation.spec.ts',
      'tests/wave1/e2e/cloudflareFoundation.spec.ts',
      'tests/wave2/e2e/pilotEntry.spec.ts',
      'tests/wave3/e2e/pilotAssessment.spec.ts',
      'tests/wave4/e2e/pilotLearning.spec.ts',
      'tests/wave5/e2e/pilotJourney.spec.ts',
    ],
    [
      'npm', 'run', 'test:e2e:run', '--', '--forbid-only',
      '--output=test-results/pilot-no-games',
      'tests/wave6/e2e/noGames.spec.ts',
    ],
    [
      'npm', 'run', 'test:e2e:run', '--', '--forbid-only',
      '--output=test-results/pilot-a11y',
      'tests/wave2/e2e/mobileLayout.spec.ts',
      'tests/wave7/e2e/qualification.spec.ts',
    ],
  ]);
  assert.equal(ROUTINE_DISPATCH_IMPLEMENTATIONS.includes('node24-curiouspathway-pilot-v1'), true);

  input.profiles[0].requiredNodeVersion = '24.21.1';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

test('resolves Portfolio Graph Linux Python 3.12 commands and leaves its workflow matrix residual', () => {
  const input = catalog();
  input.approvedImplementations.push('python312-portfolio-graph-uv-v1');
  input.profiles[0].implementationId = 'python312-portfolio-graph-uv-v1';
  delete input.profiles[0].requiredNodeVersion;
  input.profiles[0].requiredPythonVersion = '3.12.14';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-python312-ephemeral');
  assert.equal(plan.pythonVersion, '3.12.14');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.deepEqual(plan.commands, [
    ['python', '-m', 'pip', 'install', '--disable-pip-version-check', 'uv==0.11.17'],
    ['uv', 'sync', '--locked'],
    ['uv', 'run', '--locked', 'python', 'scripts/verify.py'],
    ['uv', 'run', '--locked', 'portfolio', '--help'],
    ['uv', 'run', '--locked', 'portfolio', '--version'],
    ['uv', 'run', '--locked', 'portfolio', 'doctor', '--json'],
  ]);
  assert.equal(ROUTINE_DISPATCH_IMPLEMENTATIONS.includes('python312-portfolio-graph-uv-v1'), true);

  input.profiles[0].requiredPythonVersion = '3.12.13';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

test('resolves the clean-checkout workflow on the isolated Node 22.14 disposable agent', () => {
  const input = catalog();
  input.approvedImplementations.push('node22-verify-clean-checkout-v1');
  input.profiles[0].implementationId = 'node22-verify-clean-checkout-v1';
  input.profiles[0].requiredNodeVersion = '22.14.0';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-node22-14-disposable-ephemeral');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.equal(plan.npmVersion, '10.9.2');
  assert.equal(ROUTINE_DISPATCH_IMPLEMENTATIONS.includes('node22-verify-clean-checkout-v1'), true);
  assert.deepEqual(plan.commands, [
    ['npm', 'ci'],
    ['npm', 'run', 'verify'],
    ['npm', 'run', 'verify:clean-checkout'],
  ]);

  input.profiles[0].requiredNodeVersion = '22.23.3';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

test('resolves Vercel API secret-scan and tests on the isolated Node 22.14 Gitleaks agent', () => {
  const input = catalog();
  input.approvedImplementations.push('node2214-vercel-api-gitleaks-v1');
  input.profiles[0].implementationId = 'node2214-vercel-api-gitleaks-v1';
  input.profiles[0].requiredNodeVersion = '22.14.0';
  input.profiles[0].qualification.requiredExactShaCases = 6;

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-node22-14-disposable-ephemeral');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.equal(plan.nodeVersion, '22.14.0');
  assert.equal(plan.npmVersion, '10.9.2');
  assert.deepEqual(plan.commands, [
    ['gitleaks', 'dir', '--redact', '--exit-code', '1', '--report-format', 'sarif', '--report-path', '/tmp/gitleaks.sarif', '.'],
    ['npm', 'ci', '--ignore-scripts'],
    ['npm', 'run', 'check'],
    ['npm', 'test'],
    ['npm', 'run', 'verify'],
  ]);
  assert.equal(ROUTINE_DISPATCH_IMPLEMENTATIONS.includes('node2214-vercel-api-gitleaks-v1'), true);

  input.profiles[0].requiredNodeVersion = '22.14.1';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

test('resolves Unity API maintenance on the isolated Node 22.14 disposable agent', () => {
  const input = catalog();
  const implementationId = 'node2214-unity-api-maintenance-v1';
  const profileId = 'unity-api-node2214-maintenance';
  const targetRepository = 'setnessconsulting/project-unity-api';
  input.approvedImplementations.push(implementationId);
  input.profiles[0].id = profileId;
  input.profiles[0].implementationId = implementationId;
  input.profiles[0].repositories = [targetRepository];
  input.profiles[0].requiredNodeVersion = '22.14.0';

  const plan = resolve(input, {
    profileId,
    prOverrides: {
      head: { sha, repo: { full_name: targetRepository } },
      base: { repo: { full_name: targetRepository } },
    },
    repository: targetRepository,
  });
  assert.equal(plan.repository, targetRepository);
  assert.equal(plan.profileId, profileId);
  assert.equal(plan.agentClass, 'setness-node22-14-disposable-ephemeral');
  assert.equal(plan.nodeVersion, '22.14.0');
  assert.equal(plan.npmVersion, '10.9.2');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.deepEqual(plan.commands, [
    ['npm', 'ci'],
    ['npm', 'run', 'maintenance'],
  ]);
  assert.equal(ROUTINE_DISPATCH_PROFILE_PAIRS.some(({ implementationId: admitted, repository }) =>
    admitted === implementationId && repository === targetRepository), true);

  const mispaired = structuredClone(input);
  mispaired.profiles[0].repositories = ['setnessconsulting/project-unity-api-shadow'];
  rejectsCode(() => validateProfileCatalog(mispaired), 'implementation-repository-mismatch');

  const injectedCommands = structuredClone(input);
  injectedCommands.profiles[0].commands = [['npm', 'run', 'release']];
  rejectsCode(() => validateProfileCatalog(injectedCommands), 'unexpected-field');

  input.profiles[0].requiredNodeVersion = '22.14.1';
  rejectsCode(() => resolve(input, {
    profileId,
    prOverrides: {
      head: { sha, repo: { full_name: targetRepository } },
      base: { repo: { full_name: targetRepository } },
    },
    repository: targetRepository,
  }), 'runtime-mismatch');
});

test('resolves the GitHub API foundation on the no-socket Node 22.23 profile', () => {
  const input = catalog();
  input.approvedImplementations.push('node22-github-api-foundation-v1');
  input.profiles[0].implementationId = 'node22-github-api-foundation-v1';
  input.profiles[0].requiredNodeVersion = '22.23.3';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-web-ci-node22-ephemeral');
  assert.equal(plan.nodeVersion, '22.23.3');
  assert.equal(plan.npmVersion, '10.9.9');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.deepEqual(plan.commands, [
    ['npm', 'ci', '--ignore-scripts'],
    ['npm', 'run', 'check'],
    ['npm', 'test'],
    ['npm', 'run', 'verify'],
  ]);
  assert.equal(ROUTINE_DISPATCH_IMPLEMENTATIONS.includes('node22-github-api-foundation-v1'), true);
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
  input.profiles[0].qualification.requiredExactShaCases = 5;
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

test('resolves Cloudflare API locked verification only on its pinned Python 3.12 agent', () => {
  const input = catalog();
  input.approvedImplementations.push('python312-cloudflare-api-uv-v1');
  input.profiles[0].implementationId = 'python312-cloudflare-api-uv-v1';
  delete input.profiles[0].requiredNodeVersion;
  input.profiles[0].requiredPythonVersion = '3.12.14';

  const plan = resolve(input);
  assert.equal(plan.agentClass, 'setness-python312-ephemeral');
  assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
  assert.equal(plan.pythonVersion, '3.12.14');
  assert.deepEqual(plan.commands, [
    ['python', '-m', 'pip', 'install', '--disable-pip-version-check', 'uv==0.11.17'],
    ['uv', 'sync', '--locked', '--extra', 'dev'],
    ['uv', 'run', 'python', 'scripts/verify.py'],
    ['uv', 'run', 'cloudflare-api', 'doctor', '--json'],
  ]);
  assert.equal(ROUTINE_DISPATCH_IMPLEMENTATIONS.includes('python312-cloudflare-api-uv-v1'), true);

  input.profiles[0].requiredPythonVersion = '3.12.13';
  rejectsCode(() => resolve(input), 'runtime-mismatch');
});

const python312FirstWaveImplementations = [
  ['python312-blender-api-v1', [
    ['python', '-m', 'pip', 'install', '--require-hashes', '-r', 'requirements-lock-linux-py312.txt'],
    ['python', '-m', 'pip', 'install', '--no-deps', '--no-build-isolation', '-e', '.'],
    ['python', '-m', 'ruff', 'check', '.'],
    ['python', '-m', 'mypy', 'src'],
    ['python', '-m', 'pytest', '-q'],
    [
      'python', '-m', 'pytest', '-q',
      'tests/test_batch_recovery.py', 'tests/test_batch_pipeline.py',
      'tests/test_batch.py', 'tests/test_runtime.py', 'tests/test_qualification.py',
      'tests/test_qualification_identity.py',
    ],
  ]],
  ['python312-fmod-api-v1', [
    ['python', '-m', 'pip', 'install', '.[dev]'],
    ['python', 'scripts/generate_scripting_api.py', '--check'],
    ['python', '-m', 'ruff', 'check', '.'],
    ['python', 'scripts/scan_secrets.py'],
    ['python', '-m', 'mypy', 'src'],
    ['python', '-m', 'pytest', '-q'],
    ['python', '-m', 'build'],
  ]],
  ['python312-game-maker-v1', [
    ['python', '-m', 'pip', 'install', '--upgrade', 'pip'],
    ['python', '-m', 'pip', 'install', '-e', '.[dev]'],
    ['python', '-m', 'ruff', 'check', '.'],
    ['python', '-m', 'mypy', 'src'],
    ['python', '-m', 'pytest', '-q'],
    ['python', '-m', 'game_maker', '--version'],
    ['python', '-m', 'game_maker', '--help'],
    ['python', '-m', 'game_maker', 'doctor'],
    ['python', '-m', 'game_maker', 'status'],
    [
      'python', '-c',
      "import subprocess, sys; result = subprocess.run(['git', 'status', '--porcelain'], check=True, capture_output=True, text=True); print(result.stdout, end=''); sys.exit(1 if result.stdout else 0)",
    ],
  ]],
  ['python312-context-file-maker-v1', [
    ['python', '-m', 'pip', 'install', 'pytest', 'jsonschema'],
    ['python', '-m', 'pytest', '-q'],
    ['python', 'scripts/validate.py', '--strict'],
  ]],
  ['python312-cpa-ai-pack-v1', [
    ['python', '-m', 'pip', 'install', 'pytest'],
    ['python', 'scripts/check_release.py'],
    ['python', '-m', 'pytest', '-q'],
    [
      'python', '-c',
      "import hashlib, json; from pathlib import Path; expected_raw = '2dd103d7624c1021d19f04a8b4a64fae38c2e26935cba425f88fe1a9d0a2af2c'; expected_content = 'edac0d21deb04df402e2c8715eaacfe9d4f60aaa0e31be242fd540619b157de5'; zip_path = Path('dist/ai-skills-agent-starter-pack-1.0.0.zip'); raw = hashlib.sha256(zip_path.read_bytes()).hexdigest(); recorded = json.loads(Path('RELEASE.json').read_text(encoding='utf-8'))['checksum_sha256']; print(f'raw_sha256={raw}'); print(f'release_content_checksum={recorded}'); assert raw == expected_raw; assert recorded == expected_content",
    ],
  ]],
];

const routinePython312Implementations = new Set([
  'python312-blender-api-v1',
  'python312-cloudflare-api-uv-v1',
  'python312-fmod-api-v1',
  'python312-game-maker-v1',
]);

for (const [implementationId, expectedCommands] of python312FirstWaveImplementations) {
  test(`resolves ${implementationId} to its fixed Python 3.12 command vector`, () => {
    const input = catalog();
    input.approvedImplementations.push(implementationId);
    input.profiles[0].implementationId = implementationId;
    delete input.profiles[0].requiredNodeVersion;
    input.profiles[0].requiredPythonVersion = '3.12.14';

    const plan = resolve(input);
    assert.equal(plan.agentClass, 'setness-python312-ephemeral');
    assert.equal(plan.requiredCheck, 'jenkins-pr-gate');
    assert.equal(plan.pythonVersion, '3.12.14');
    assert.equal(Object.hasOwn(plan, 'nodeVersion'), false);
    assert.deepEqual(plan.commands, expectedCommands);
    assert.equal(
      ROUTINE_DISPATCH_IMPLEMENTATIONS.includes(implementationId),
      routinePython312Implementations.has(implementationId),
    );

    input.profiles[0].requiredPythonVersion = '3.12.13';
    rejectsCode(() => resolve(input), 'runtime-mismatch');
  });
}

test('rejects profile fields that could inject commands or credentials', () => {
  const input = catalog();
  input.profiles[0].commands = ['curl attacker.invalid'];
  rejectsCode(() => resolve(input), 'unexpected-field');
});

test('accepts complete exact-SHA evidence for the centrally reviewed standard matrix', () => {
  const input = catalog();
  input.profiles[0].status = 'qualified';
  input.profiles[0].qualification = {
    requiredExactShaCases: 4,
    qualifiedExactShaCases: 4,
    state: 'passed',
    evidenceReference: 'qualification/evidence-matrix.md',
  };
  assert.deepEqual(validateProfileCatalog(input), { profileCount: 1, implementationCount: 1 });

  input.profiles[0].qualification.requiredExactShaCases = 0;
  input.profiles[0].qualification.qualifiedExactShaCases = 0;
  input.profiles[0].qualification.state = 'in-progress';
  rejectsCode(() => validateProfileCatalog(input), 'qualification-matrix-mismatch');
});

test('rejects undersized matrices, including for the six-case Vercel profile', () => {
  const undersizedStandard = catalog();
  undersizedStandard.profiles[0].qualification = {
    requiredExactShaCases: 1,
    qualifiedExactShaCases: 1,
    state: 'passed',
    evidenceReference: 'qualification/evidence-matrix.md',
  };
  rejectsCode(() => validateProfileCatalog(undersizedStandard), 'qualification-matrix-mismatch');

  const vercel = catalog();
  vercel.approvedImplementations.push('node2214-vercel-api-gitleaks-v1');
  vercel.profiles[0].id = 'project-vercel-api-node2214-gitleaks';
  vercel.profiles[0].implementationId = 'node2214-vercel-api-gitleaks-v1';
  vercel.profiles[0].requiredNodeVersion = '22.14.0';
  vercel.profiles[0].qualification = {
    requiredExactShaCases: 6,
    qualifiedExactShaCases: 6,
    state: 'passed',
    evidenceReference: 'docs/project-vercel-api-shadow-2026-09-30.md',
  };
  assert.deepEqual(validateProfileCatalog(vercel), { profileCount: 1, implementationCount: 2 });

  vercel.profiles[0].qualification.requiredExactShaCases = 1;
  vercel.profiles[0].qualification.qualifiedExactShaCases = 1;
  rejectsCode(() => validateProfileCatalog(vercel), 'qualification-matrix-mismatch');
});

test('applies reviewed case counts to active catalog profiles without an installed adapter', () => {
  for (const implementationId of ['jenkins-repository-contract', 'setness-repository-pilot']) {
    const input = catalog();
    input.approvedImplementations.push(implementationId);
    input.profiles[0].implementationId = implementationId;
    input.profiles[0].qualification = {
      requiredExactShaCases: 1,
      qualifiedExactShaCases: 1,
      state: 'passed',
      evidenceReference: 'qualification/evidence-matrix.md',
    };
    rejectsCode(() => validateProfileCatalog(input), 'qualification-matrix-mismatch');
  }
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

test('Setness primary CI profile maps only its centrally defined Node 22 commands', () => {
  const input = catalog();
  input.approvedImplementations = ['setness-web-ci-node22-v1'];
  input.profiles[0].implementationId = 'setness-web-ci-node22-v1';
  input.profiles[0].repositories = ['setnessconsulting/project-setness-consulting'];
  input.profiles[0].requiredNodeVersion = '22.23.3';
  input.profiles[0].qualification = {
    requiredExactShaCases: 4,
    qualifiedExactShaCases: 0,
    state: 'in-progress',
  };
  const pullRequest = pr();
  pullRequest.head.repo.full_name = 'setnessconsulting/project-setness-consulting';
  pullRequest.base.repo.full_name = 'setnessconsulting/project-setness-consulting';
  const execution = resolveAuthorizedShadowPullRequest(input, 'example-foundation', pullRequest, {
    repository: 'setnessconsulting/project-setness-consulting',
    pullRequestNumber: 17,
    headSha: sha,
    allowedAuthors: ['setnessconsulting'],
  });
  assert.equal(execution.requiredCheck, 'jenkins-pr-gate');
  assert.equal(execution.nodeVersion, '22.23.3');
  assert.deepEqual(execution.commands, IMPLEMENTATIONS['setness-web-ci-node22-v1'].commands);
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
