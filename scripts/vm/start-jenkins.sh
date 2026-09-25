#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

action="${1:-start}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
secret_dir="/etc/setness-jenkins/secrets"
admin_password_file="${secret_dir}/admin-password"
compose=(docker compose --project-directory "$repo_root" --env-file "$repo_root/.env" --profile build-images)

fail() {
  printf 'Jenkins VM setup: %s\n' "$1" >&2
  exit 1
}

if [[ "$(uname -s)" != Linux ]] || [[ "$(grep -Eqi 'microsoft|wsl' /proc/version && printf wsl || true)" == wsl ]]; then
  fail 'run only inside the dedicated Ubuntu Hyper-V guest; Docker Desktop and WSL are not pilot hosts.'
fi

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [[ "$virt" != microsoft && "$virt" != hyperv ]]; then
  fail 'the guest virtualization identity is not Hyper-V; no local Docker daemon will be used as a substitute.'
fi

[[ -f "$repo_root/compose.yaml" && -f "$repo_root/.env" ]] || fail 'checked-in Compose and ignored local .env are required.'
[[ -S /var/run/docker.sock ]] || fail 'the guest Docker socket is unavailable.'
if grep -Eq '^(JENKINS_ADMIN_PASSWORD|JENKINS_AGENT_SECRET|GITHUB_APP_KEY|JENKINS_APP_PRIVATE_KEY)=' "$repo_root/.env"; then
  fail 'local .env may contain non-secret wiring only; remove secret-valued settings.'
fi

if [[ "$action" == init-secrets ]]; then
  if [[ -e "$admin_password_file" ]]; then
    fail 'an administrator secret already exists; refusing to replace it.'
  fi
  sudo install -d -m 0700 -o root -g root "$secret_dir"
  secret_tmp="$(sudo mktemp "$secret_dir/admin-password.XXXXXX")"
  sudo sh -c 'umask 077; openssl rand -base64 48 | tr -d "\\n" > "$1"' sh "$secret_tmp"
  sudo chown root:root "$secret_tmp"
  sudo chmod 0600 "$secret_tmp"
  sudo mv -- "$secret_tmp" "$admin_password_file"
  printf 'Created a protected Jenkins administrator secret. Read it only in the VM console when provisioning the GitHub App credential.\n'
  exit 0
fi

[[ -f "$admin_password_file" ]] || fail "bootstrap the protected administrator secret first: $admin_password_file"
[[ "$(stat -c '%a' "$admin_password_file")" == 600 ]] || fail 'the administrator secret must have mode 0600.'
[[ "$(stat -c '%a' "$secret_dir")" == 700 ]] || fail 'the secret directory must have mode 0700.'

export DOCKER_SOCKET_GID="$(stat -c '%g' /var/run/docker.sock)"
export JENKINS_ADMIN_ID='jenkins-admin'
if [[ "$action" == start || "$action" == install || "$action" == restart ]]; then
  export JENKINS_ADMIN_PASSWORD="$(<"$admin_password_file")"
  [[ -n "$JENKINS_ADMIN_PASSWORD" ]] || fail 'the bootstrap administrator secret is empty.'
else
  export JENKINS_ADMIN_PASSWORD='compose-inspection-only'
fi

cleanup() {
  unset JENKINS_ADMIN_PASSWORD DOCKER_SOCKET_GID JENKINS_ADMIN_ID
}
trap cleanup EXIT

case "$action" in
  start|install|restart)
    docker info --format '{{.OperatingSystem}}' >/dev/null || fail 'the guest Docker daemon is not ready.'
    "${compose[@]}" config --quiet
    if [[ "$action" == install || "$action" == restart ]]; then
      "${compose[@]}" build controller agent-image node24-agent-image e2e-agent-image
    fi
    if [[ "$action" == restart ]]; then
      "${compose[@]}" up -d --force-recreate controller
    else
      "${compose[@]}" up -d controller
    fi
    printf 'Jenkins controller started in the protected Hyper-V guest. The old Docker Desktop volume is not referenced.\n'
    ;;
  stop)
    "${compose[@]}" stop controller
    printf 'Jenkins controller stopped; the persistent VM volume was preserved.\n'
    ;;
  status)
    "${compose[@]}" ps
    ;;
  logs)
    "${compose[@]}" logs --tail 100 controller
    ;;
  *)
    fail 'usage: bash scripts/vm/start-jenkins.sh {init-secrets|install|start|restart|stop|status|logs}'
    ;;
esac
