#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

fail() {
  printf 'Jenkins backup: %s\n' "$1" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail 'run with sudo inside the dedicated VM.'
virt="$(systemd-detect-virt 2>/dev/null || true)"
[[ "$virt" == microsoft || "$virt" == hyperv ]] || fail 'backup is allowed only inside the dedicated Hyper-V guest.'

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
volume_name='setness-jenkins-vm-home'
expected_volume_path="/var/lib/docker/volumes/${volume_name}/_data"
backup_root='/var/backups/setness-jenkins'
secret_root='/etc/setness-jenkins/secrets'
controller_image='jenkins-pilot-controller:2.568.3-pilot1'
agent_image='jenkins-pilot-agent:node-22.23.2'

[[ -f "$repo_root/compose.yaml" && -f "$repo_root/.env" ]] || fail 'the checked-out Compose repository and ignored .env are required.'
[[ "$(stat -c '%a' "$repo_root/.env")" == 600 ]] || fail 'the ignored runtime .env must be mode 0600 before it is backed up.'
if grep -Eq '^[[:space:]]*(JENKINS_ADMIN_PASSWORD|JENKINS_AGENT_SECRET|GITHUB_APP_KEY|GITHUB_APP_PRIVATE_KEY|JENKINS_APP_PRIVATE_KEY)=' "$repo_root/.env"; then
  fail 'the ignored runtime .env contains a forbidden secret field and will not be archived.'
fi
git -c safe.directory="$repo_root" -C "$repo_root" diff --quiet && git -c safe.directory="$repo_root" -C "$repo_root" diff --cached --quiet || fail 'commit or discard tracked configuration changes before creating a recovery backup.'
[[ -z "$(git -c safe.directory="$repo_root" -C "$repo_root" status --porcelain --untracked-files=all)" ]] || fail 'the Jenkins configuration checkout must be clean; ignored .env is intentionally excluded from this check.'
[[ -f "${secret_root}/admin-password" ]] || fail 'the protected controller bootstrap secret is missing.'
[[ "$(stat -c '%a' "$secret_root")" == 700 && "$(stat -c '%a' "${secret_root}/admin-password")" == 600 ]] || fail 'the bootstrap secret directory and file must be mode 0700 and 0600.'

controller_ids="$(docker ps --filter 'label=com.docker.compose.project=setness-jenkins-vm' --filter 'label=com.docker.compose.service=controller' --format '{{.ID}}')"
[[ -z "$controller_ids" ]] || fail 'stop the Jenkins controller before taking a consistent backup.'
agent_ids="$(docker ps --filter "ancestor=${agent_image}" --format '{{.ID}}')"
[[ -z "$agent_ids" ]] || fail 'wait for all one-use build containers to be removed before backing up.'
volume_users="$(docker ps --filter "volume=${volume_name}" --format '{{.ID}}')"
[[ -z "$volume_users" ]] || fail 'a running container still uses the Jenkins home volume; stop it before taking a consistent backup.'

volume_path="$(docker volume inspect --format '{{.Mountpoint}}' "$volume_name" 2>/dev/null)" || fail 'the expected fresh Jenkins home volume was not found.'
[[ "$(realpath -e -- "$volume_path")" == "$expected_volume_path" ]] || fail 'the Jenkins volume mountpoint differs from the expected VM-local path.'
[[ -f "${volume_path}/secrets/master.key" && ! -L "${volume_path}/secrets/master.key" ]] || fail 'Jenkins master.key is absent or is not a regular file.'
[[ -f "${volume_path}/secrets/hudson.util.Secret" && ! -L "${volume_path}/secrets/hudson.util.Secret" ]] || fail 'Jenkins hudson.util.Secret is absent or is not a regular file.'

install -d -o root -g root -m 0700 "$backup_root"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
destination="${backup_root}/jenkins-${stamp}"
[[ ! -e "$destination" ]] || fail 'a backup with this timestamp already exists; wait and retry.'
config_commit="$(git -c safe.directory="$repo_root" -C "$repo_root" rev-parse HEAD)"
staging="$(mktemp -d "${backup_root}/.staging.XXXXXXXX")"
cleanup() { [[ -z "${staging:-}" ]] || rm -rf -- "$staging"; }
trap cleanup EXIT

tar --numeric-owner --xattrs --acls -C "$volume_path" -czf "${staging}/jenkins-home.tar.gz" .
tar --numeric-owner --xattrs --acls -C /etc/setness-jenkins -czf "${staging}/host-secrets.tar.gz" secrets
tar --numeric-owner --xattrs --acls -C "$repo_root" -czf "${staging}/runtime-config.tar.gz" .env
cat > "${staging}/manifest.txt" <<EOF
format=1
created_utc=${stamp}
jenkins_volume=${volume_name}
project_jenkins_commit=${config_commit}
contains_master_key=true
contains_hudson_secret=true
host_secrets_archive=secrets/
runtime_config_archive=.env
EOF
(cd "$staging" && sha256sum jenkins-home.tar.gz host-secrets.tar.gz runtime-config.tar.gz > SHA256SUMS)
chmod 0600 "${staging}/jenkins-home.tar.gz" "${staging}/host-secrets.tar.gz" "${staging}/runtime-config.tar.gz" "${staging}/manifest.txt" "${staging}/SHA256SUMS"
mv -- "$staging" "$destination"
staging=''
trap - EXIT

printf 'Protected Jenkins backup created at %s. It contains the complete stopped Jenkins home and root-only host secrets; keep it on the encrypted VM disk unless separately encrypted before transfer.\n' "$destination"
