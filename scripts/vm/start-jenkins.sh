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


# Groovy handed to the controller Script Console to report the loaded
# portfolio posture, including whether each job's rendered script is
# approved. Approval state is asked of script-security directly: pending
# entries persist after a script is no longer rendered, so counting them
# would report stale failures. The trailing summary exists so an operator can
# tell "no portfolio job is loaded" apart from "loaded and approved" without
# reading every job line.
portfolio_posture_script() {
  cat <<'PORTFOLIO_POSTURE'
import org.jenkinsci.plugins.scriptsecurity.scripts.Language
import org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval

def sa = ScriptApproval.get()
def jenkins = jenkins.model.Jenkins.get()
def groovyLanguage = jenkins.getExtensionList(Language.class).find { it.getName().equalsIgnoreCase('groovy') }
println 'PORTFOLIO_EXECUTORS=' + jenkins.getNumExecutors()
// The trusted dispatch path (poller -> gate) needs the queue step, the steps
// the gate publishes its check run with, and an agent cloud. Report them here so
// a controller image that silently lost a plugin fails deploy verification
// instead of failing a poll five minutes later. The poller asserts the same set
// at the start of every run.
def capabilityPlugins = ['pipeline-build-step', 'github-checks', 'workflow-cps', 'workflow-basic-steps', 'workflow-durable-task-step', 'workflow-job', 'workflow-scm-step', 'github-branch-source', 'docker-plugin']
def capabilitySymbols = ['build', 'withChecks', 'publishChecks', 'checkout', 'node', 'sh', 'writeFile', 'readFile', 'timeout', 'echo', 'error']
def capabilityGaps = []
def capabilityPluginManager = jenkins.getPluginManager()
capabilityPlugins.each { name ->
    def plugin = capabilityPluginManager.getPlugin(name)
    if (plugin == null || !plugin.isActive()) capabilityGaps.add('plugin ' + name)
}
try {
    def availableSymbols = jenkins.getDescriptorList(org.jenkinsci.plugins.workflow.steps.Step.class).collect { descriptor -> descriptor.functionName } as Set
    capabilitySymbols.each { symbol ->
        if (!availableSymbols.contains(symbol)) capabilityGaps.add('step ' + symbol)
    }
} catch (Throwable failure) {
    capabilityGaps.add('step enumeration (' + failure.getClass().getSimpleName() + ')')
}
// This core exposes the configured clouds as the `clouds` property; it has no
// getClouds() accessor.
try {
    if (!jenkins.clouds) capabilityGaps.add('agent cloud')
} catch (Throwable failure) {
    capabilityGaps.add('agent cloud enumeration (' + failure.getClass().getSimpleName() + ')')
}
println 'PORTFOLIO_CAPABILITIES=' + (capabilityGaps.isEmpty() ? 'ok' : 'missing: ' + capabilityGaps.join('; '))
// No build agent may reach the guest Docker socket. docker-plugin reads these
// CasC mounts when it creates each one-use container, so a template that gains
// a socket bind silently hands daemon access (effectively host root) to
// repository-controlled code. Report the count instead of trusting the file.
def socketMountingTemplates = []
jenkins.clouds.each { cloud ->
    def agentTemplates = null
    try {
        agentTemplates = cloud.getTemplates()
    } catch (Throwable failure) {
        socketMountingTemplates.add('enumeration(' + failure.getClass().getSimpleName() + ')')
        return
    }
    (agentTemplates ?: []).each { agentTemplate ->
        def agentMounts = []
        try {
            agentMounts = (agentTemplate.getDockerTemplateBase()?.getMounts() ?: [])
        } catch (Throwable failure) {
            socketMountingTemplates.add(agentTemplate.name.toString() + '(mounts-unreadable)')
            return
        }
        if (agentMounts.any { it.toString().contains('docker.sock') }) {
            socketMountingTemplates.add(agentTemplate.name.toString())
        }
    }
}
println 'PORTFOLIO_AGENT_SOCKET_MOUNTS=' + (socketMountingTemplates.isEmpty() ? '0' : socketMountingTemplates.size() + ' ' + socketMountingTemplates.join(','))
def loaded = 0
def approved = 0
def unapproved = 0
def withoutScript = 0
def missing = 0
['portfolio-dispatch/portfolio-pr-gate',
 'portfolio-dispatch/portfolio-pr-poller',
 'portfolio-dispatch/portfolio-checkout-credential-reaper'].each { full ->
    def job = jenkins.getItemByFullName(full)
    if (job == null) {
        missing++
        println 'PORTFOLIO_JOB ' + full + ' state=missing script=missing'
        return
    }
    loaded++
    def definition = job.getDefinition()
    def script = null
    try {
        script = definition?.getScript()
    } catch (Exception ignored) {
        script = null
    }
    def scriptState = 'no-script'
    if (script != null) {
        scriptState = sa.isScriptApproved(script, groovyLanguage) ? 'approved' : 'unapproved'
    }
    if (scriptState == 'approved') {
        approved++
    } else if (scriptState == 'unapproved') {
        unapproved++
    } else {
        withoutScript++
    }
    println 'PORTFOLIO_JOB ' + full + ' state=' + (job.isDisabled() ? 'disabled' : 'enabled') + ' script=' + scriptState
}
println 'PORTFOLIO_SUMMARY loaded=' + loaded + ' approved=' + approved + ' unapproved=' + unapproved + ' no-script=' + withoutScript + ' missing=' + missing
PORTFOLIO_POSTURE
}

# Post-load verification of the centrally rendered portfolio jobs. Every
# portfolio job uses sandbox(false), so its rendered script must be approved
# in script-security before the job can run, and an unapproved script fails
# the build within milliseconds. Provisioning and restart therefore verify it
# explicitly. This never approves anything itself: approving privileged
# controller code stays a deliberate operator action. Enabled state is
# reported rather than asserted, because a job may be enabled deliberately for
# a qualification run, so the operator reads the report for the default posture.
portfolio_verify() {
  local container ready=0 admin_password bind_ip http_port response
  local cookie_jar crumb_json crumb crumb_field netrc_file script_file
  container="$("${compose[@]}" ps -q controller 2>/dev/null || true)"
  if [[ -z "$container" ]]; then
    printf 'Portfolio verification: the controller container is not running.\n' >&2
    return 1
  fi
  for _ in $(seq 1 60); do
    if docker exec "$container" curl --fail --silent --output /dev/null http://127.0.0.1:8080/login >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 2
  done
  if [[ "$ready" != 1 ]]; then
    printf 'Portfolio verification: Jenkins did not answer on the controller within 120 seconds.\n' >&2
    return 1
  fi
  admin_password="$(<"$admin_password_file")"
  if [[ -z "$admin_password" ]]; then
    printf 'Portfolio verification FAILED: the protected administrator secret is empty.\n' >&2
    return 1
  fi
  # The ignored .env may carry CRLF line endings when it was authored on Windows,
  # so strip any carriage return before using a value in a URL.
  bind_ip="$(sed -n 's/^JENKINS_HTTP_BIND_IP=//p' "$repo_root/.env" | tr -d '\r' | tail -1)"
  http_port="$(sed -n 's/^JENKINS_HTTP_PORT=//p' "$repo_root/.env" | tr -d '\r' | tail -1)"
  bind_ip="${bind_ip:-127.0.0.1}"
  http_port="${http_port:-18080}"
  # The administrator secret and the probe body are handed to curl by file, not
  # on the command line, so neither appears in the process table. umask 077
  # already restricts these temporary files to the invoking user.
  cookie_jar="$(mktemp)"
  netrc_file="$(mktemp)"
  script_file="$(mktemp)"
  printf 'machine %s login jenkins-admin password %s\n' "$bind_ip" "$admin_password" > "$netrc_file"
  portfolio_posture_script > "$script_file"
  crumb_json="$(curl --silent --netrc-file "$netrc_file" --cookie-jar "$cookie_jar" "http://${bind_ip}:${http_port}/crumbIssuer/api/json" 2>/dev/null || true)"
  crumb="$(printf '%s' "$crumb_json" | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')"
  crumb_field="$(printf '%s' "$crumb_json" | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')"
  if [[ -n "$crumb" && -n "$crumb_field" ]]; then
    response="$(curl --silent --show-error --netrc-file "$netrc_file" --cookie "$cookie_jar" --header "${crumb_field}: ${crumb}" --data-urlencode "script@${script_file}" "http://${bind_ip}:${http_port}/scriptText" 2>/dev/null || true)"
  else
    response=""
  fi
  rm -f "$cookie_jar" "$netrc_file" "$script_file"
  unset admin_password cookie_jar crumb_json crumb crumb_field netrc_file script_file
  printf '%s\n' "$response" | grep '^PORTFOLIO_' || true
  if ! printf '%s\n' "$response" | grep -q '^PORTFOLIO_'; then
    printf 'Portfolio verification FAILED: the controller did not report a portfolio posture; treat the loaded portfolio jobs as unverified.\n' >&2
    return 1
  fi
  if ! printf '%s\n' "$response" | grep -q '^PORTFOLIO_AGENT_SOCKET_MOUNTS=0$'; then
    printf 'Portfolio verification FAILED: at least one Jenkins agent template still receives the guest Docker socket, or the controller could not read the agent templates at all (expected PORTFOLIO_AGENT_SOCKET_MOUNTS=0). A socket bind gives repository-controlled code daemon access that is effectively host root, so this is a security boundary, not a convenience setting. When this ran as part of install or restart the controller is already running, so a non-zero exit means the fleet is not at its intended boundary yet, not that the controller failed to start.\n' >&2
    return 1
  fi
  if printf '%s\n' "$response" | grep -q 'script=unapproved'; then
    printf 'Portfolio verification FAILED: at least one loaded portfolio job script is not approved, and such a job fails immediately at run time. Review it in Manage Jenkins -> Script Console, approve it deliberately, then rerun this check. When this ran as part of install or restart the controller is already running, so a non-zero exit means the portfolio jobs cannot run yet, not that the controller failed to start; re-running the same action is idempotent.\n' >&2
    return 1
  fi
  if printf '%s\n' "$response" | grep -q '^PORTFOLIO_SUMMARY loaded=0 '; then
    printf 'Portfolio verification passed: no portfolio-dispatch job is loaded, so there is nothing to verify. The portfolio gate is created only when a catalog repository is configured, so this is the expected default posture.\n'
    return 0
  fi
  if ! printf '%s\n' "$response" | grep -q '^PORTFOLIO_CAPABILITIES=ok$'; then
    printf 'Portfolio verification FAILED: the controller did not report an intact portfolio dispatch capability set (expected PORTFOLIO_CAPABILITIES=ok). The poller refuses to dispatch and the gate cannot queue or publish checks until the missing plugin, step, or agent-cloud capability is restored in the controller image. When this ran as part of install or restart the controller is already running, so a non-zero exit means the portfolio jobs cannot dispatch shadow evidence yet, not that the controller failed to start; re-running the same action after fixing the image is idempotent.\n' >&2
    return 1
  fi
  printf 'Portfolio verification passed: every loaded portfolio job reports an approved script and the controller reports the required dispatch capabilities. Re-rendering a job script changes it, so re-run this check after any configuration change.\n'
}

case "$action" in
  start|install|restart)
    docker info --format '{{.OperatingSystem}}' >/dev/null || fail 'the guest Docker daemon is not ready.'
    "${compose[@]}" config --quiet
    if [[ "$action" == start ]] && ! docker image inspect 'jenkins-pilot-agent:node-22.14.0' >/dev/null 2>&1; then
      "${compose[@]}" build node22-14-agent-image
    fi
    if [[ "$action" == start ]] && ! docker image inspect 'jenkins-pilot-agent:node-22.14.0-disposable' >/dev/null 2>&1; then
      "${compose[@]}" build node22-14-disposable-agent-image
    fi
    if [[ "$action" == start ]] && ! docker image inspect 'jenkins-pilot-agent:setness-web-ci-node22-pwsh-7.6.6' >/dev/null 2>&1; then
      "${compose[@]}" build setness-web-ci-agent-image
    fi
    if [[ "$action" == start ]] && ! docker image inspect 'jenkins-pilot-agent:python-3.12.14' >/dev/null 2>&1; then
      "${compose[@]}" build python312-agent-image
    fi
    if [[ "$action" == install || "$action" == restart ]]; then
      "${compose[@]}" build controller agent-image node22-14-agent-image node22-14-disposable-agent-image setness-web-ci-agent-image node24-agent-image python312-agent-image e2e-agent-image secondary-agent-image
    fi
    if [[ "$action" == restart ]]; then
      "${compose[@]}" up -d --force-recreate controller
    else
      "${compose[@]}" up -d controller
    fi
    printf 'Jenkins controller started in the protected Hyper-V guest. The old Docker Desktop volume is not referenced.\n'
    if [[ "$action" == start ]]; then
      printf 'Run `bash scripts/vm/start-jenkins.sh verify` once Jenkins is ready to confirm every loaded portfolio job script is approved.\n'
    else
      portfolio_verify
    fi
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
  verify)
    portfolio_verify
    ;;
  *)
    fail 'usage: bash scripts/vm/start-jenkins.sh {init-secrets|install|start|restart|stop|status|logs|verify}'
    ;;
esac
