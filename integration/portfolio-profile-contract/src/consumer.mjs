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
  'node22-foundation-v1': Object.freeze({
    agentClass: 'setness-ephemeral',
    nodeVersion: '22.23.3',
    requiredCheck: 'jenkins-pr-gate',
    commands: Object.freeze([
      Object.freeze(['npm', 'ci', '--ignore-scripts']),
      Object.freeze(['npm', 'run', 'check']),
      Object.freeze(['npm', 'test']),
      Object.freeze(['npm', 'run', 'verify']),
    ]),
  }),
});

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

function validateQualification(qualification, profileId) {
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
  if (state === 'passed' && (requiredExactShaCases < 10
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
        || new Set(profile.repositories).size !== profile.repositories.length
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
    validateQualification(profile.qualification, profile.id);

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
          || profile.qualification.requiredExactShaCases < 10) {
        reject('unapproved-profile', `profile ${profile.id} must select an approved implementation and require ten cases`);
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
      if (repositoryOwners.has(repository)) {
        reject('duplicate-repository-profile', `repository ${repository} is assigned to multiple profiles`);
      }
      repositoryOwners.set(repository, profile.id);
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
  if (profile.status !== 'shadow') reject('profile-not-shadow', 'only an explicitly shadow-enabled profile may execute');
  if (profile.repositories.length !== 1) reject('ambiguous-profile', 'an executable profile must identify exactly one repository');
  const implementation = IMPLEMENTATIONS[profile.implementationId];
  if (!implementation) reject('implementation-not-installed', 'no centrally trusted adapter is installed for this profile');
  if (!profile.checkNames.includes(implementation.requiredCheck)) {
    reject('required-check-missing', 'profile does not declare the centrally required gate');
  }
  if (profile.requiredNodeVersion !== implementation.nodeVersion) {
    reject('runtime-mismatch', 'profile Node.js version does not match the centrally pinned agent runtime');
  }

  return Object.freeze({
    profileId: profile.id,
    repository: profile.repositories[0],
    headSha: headSha.toLowerCase(),
    requiredCheck: implementation.requiredCheck,
    agentClass: implementation.agentClass,
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
