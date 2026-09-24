#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

backup_directory="${1:-}"
container_started=0
admin_password=''

fail() {
  printf 'Jenkins restore drill: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [[ "$container_started" == 1 ]]; then
    docker rm -f "$container_name" >/dev/null 2>&1 || true
  fi
  unset JENKINS_HOME_VOLUME JENKINS_ADMIN_ID JENKINS_ADMIN_PASSWORD DOCKER_SOCKET_GID
  admin_password=''
}
trap cleanup EXIT

[[ "${EUID}" -eq 0 ]] || fail 'run with sudo inside the dedicated VM.'
virt="$(systemd-detect-virt 2>/dev/null || true)"
[[ "$virt" == microsoft || "$virt" == hyperv ]] || fail 'restore testing is allowed only inside the dedicated Hyper-V guest.'

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
backup_root='/var/backups/setness-jenkins'
controller_image='jenkins-pilot-controller:2.568.3-pilot1'
agent_image='jenkins-pilot-agent:node-22.23.2'
[[ -n "$backup_directory" ]] || fail 'pass one backup directory created by backup-jenkins.sh.'
backup_directory="$(realpath -e -- "$backup_directory")"
[[ "$backup_directory" == "$backup_root"/* ]] || fail 'the selected backup is outside the protected local backup directory.'
[[ -f "${backup_directory}/jenkins-home.tar.gz" && -f "${backup_directory}/host-secrets.tar.gz" && -f "${backup_directory}/runtime-config.tar.gz" && -f "${backup_directory}/manifest.txt" && -f "${backup_directory}/SHA256SUMS" ]] || fail 'the selected backup is incomplete.'

cd "$backup_directory"
sha256sum --check --status SHA256SUMS || fail 'backup checksums do not match.'
for archive in jenkins-home.tar.gz host-secrets.tar.gz runtime-config.tar.gz; do
  if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    fail 'backup archive contains an unsafe absolute or parent-relative path.'
  fi
done

[[ -f "${repo_root}/compose.yaml" && -f "${repo_root}/.env" ]] || fail 'the checked-out Compose repository and ignored .env are required.'
config_commit="$(sed -n 's/^project_jenkins_commit=//p' "${backup_directory}/manifest.txt")"
[[ "$config_commit" =~ ^([a-fA-F0-9]{40}|[a-fA-F0-9]{64})$ ]] || fail 'the backup does not identify a full Git commit for its checked-in configuration.'
[[ "$(git -c safe.directory="$repo_root" -C "$repo_root" rev-parse HEAD)" == "$config_commit" ]] || fail 'check out the exact project-jenkins commit recorded in the backup before rehearsing restoration.'
git -c safe.directory="$repo_root" -C "$repo_root" diff --quiet && git -c safe.directory="$repo_root" -C "$repo_root" diff --cached --quiet || fail 'the Jenkins configuration checkout must be clean for restore testing.'
[[ -z "$(git -c safe.directory="$repo_root" -C "$repo_root" status --porcelain --untracked-files=all)" ]] || fail 'the Jenkins configuration checkout must be clean; ignored .env is intentionally excluded from this check.'
controller_ids="$(docker ps --filter 'label=com.docker.compose.project=setness-jenkins-vm' --filter 'label=com.docker.compose.service=controller' --format '{{.ID}}')"
[[ -z "$controller_ids" ]] || fail 'stop the pilot controller before restore testing.'
agent_ids="$(docker ps --filter "ancestor=${agent_image}" --format '{{.ID}}')"
[[ -z "$agent_ids" ]] || fail 'wait for one-use build containers to be removed before restore testing.'

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
restore_volume="setness-jenkins-restore-${stamp}"
container_name="setness-jenkins-restore-${stamp}"
secret_destination="${backup_root}/restore-drills/${stamp}"
if docker volume inspect "$restore_volume" >/dev/null 2>&1; then
  fail 'the generated restore volume name already exists; no existing volume will be reused.'
fi
[[ ! -e "$secret_destination" ]] || fail 'the generated restore-secret directory already exists; no existing data will be reused.'
install -d -o root -g root -m 0700 "${backup_root}/restore-drills" "$secret_destination"

docker volume create "$restore_volume" >/dev/null
volume_path="$(docker volume inspect --format '{{.Mountpoint}}' "$restore_volume")"
expected_volume_path="/var/lib/docker/volumes/${restore_volume}/_data"
[[ "$(realpath -e -- "$volume_path")" == "$expected_volume_path" ]] || fail 'the restore volume mountpoint differs from the expected VM-local path.'
tar --numeric-owner --xattrs --acls -xzf "${backup_directory}/jenkins-home.tar.gz" -C "$volume_path"
[[ -f "${volume_path}/secrets/master.key" && -f "${volume_path}/secrets/hudson.util.Secret" ]] || fail 'the restored Jenkins encryption material is incomplete.'

config_destination="${secret_destination}/runtime-config"
install -d -o root -g root -m 0700 "$config_destination"
tar --numeric-owner --xattrs --acls -xzf "${backup_directory}/runtime-config.tar.gz" -C "$config_destination"
restore_env_file="${config_destination}/.env"
[[ -f "$restore_env_file" && "$(stat -c '%a' "$restore_env_file")" == 600 ]] || fail 'the restored runtime .env is missing or has unsafe permissions.'
if grep -Eq '^[[:space:]]*(JENKINS_ADMIN_PASSWORD|JENKINS_AGENT_SECRET|GITHUB_APP_KEY|GITHUB_APP_PRIVATE_KEY|JENKINS_APP_PRIVATE_KEY)=' "$restore_env_file"; then
  fail 'the restored runtime .env contains a forbidden secret field.'
fi

tar --numeric-owner --xattrs --acls -xzf "${backup_directory}/host-secrets.tar.gz" -C "$secret_destination"
admin_password_file="${secret_destination}/secrets/admin-password"
[[ -f "$admin_password_file" && "$(stat -c '%a' "$admin_password_file")" == 600 ]] || fail 'the restored host bootstrap secret is missing or has unsafe permissions.'
admin_password="$(<"$admin_password_file")"
[[ -n "$admin_password" ]] || fail 'the restored bootstrap secret is empty.'

export JENKINS_HOME_VOLUME="$restore_volume"
export JENKINS_ADMIN_ID='jenkins-admin'
export JENKINS_ADMIN_PASSWORD="$admin_password"
export DOCKER_SOCKET_GID="$(stat -c '%g' /var/run/docker.sock)"
compose=(docker compose --project-directory "$repo_root" --env-file "$restore_env_file" --profile restore-check)

container_started=1
"${compose[@]}" run --detach --no-deps --name "$container_name" restore-check >/dev/null

ready=0
for _ in $(seq 1 180); do
  if docker logs "$container_name" 2>&1 | grep -Fq 'Jenkins is fully up and running'; then
    ready=1
    break
  fi
  state="$(docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null || true)"
  if [[ "$state" != running ]]; then
    break
  fi
  sleep 1
done

if [[ "$ready" -ne 1 ]]; then
  fail "restored controller did not reach the Jenkins-ready marker. The restore volume '$restore_volume' and root-only secret copy were retained for local diagnosis; the temporary container will be removed."
fi

docker rm -f "$container_name" >/dev/null
container_started=0
printf 'Restore drill passed: isolated Jenkins reached its ready marker with restored encryption material. The retained volume is %s; the root-only bootstrap secret copy is under %s. No network or Docker socket was available to the drill controller.\n' "$restore_volume" "$secret_destination"
