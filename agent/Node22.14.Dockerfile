FROM jenkins/inbound-agent:3355.v388858a_47b_33-14-jdk21@sha256:c3d5dd3c9ca922032daccf8c6226cb877a13b45a4e2e3953c443b4aa9af55e81

USER root

# This agent ships no Docker CLI and joins no docker group. The guest Docker
# socket stays on the controller (Compose) and no template mounts it back in,
# so a client here would have no daemon to reach.
RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends ca-certificates curl git openssh-client xz-utils; \
    rm -rf /var/lib/apt/lists/*; \
    curl --fail --location --silent --show-error \
      https://github.com/gitleaks/gitleaks/releases/download/v8.24.3/gitleaks_8.24.3_linux_x64.tar.gz \
      --output /tmp/gitleaks_8.24.3_linux_x64.tar.gz; \
    printf '%s  %s\n' \
      '9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c' \
      '/tmp/gitleaks_8.24.3_linux_x64.tar.gz' | sha256sum --check --strict; \
    tar --extract --gzip --file /tmp/gitleaks_8.24.3_linux_x64.tar.gz \
      --directory /tmp gitleaks; \
    install -o root -g root -m 0755 /tmp/gitleaks /usr/local/bin/gitleaks; \
    rm -f /tmp/gitleaks /tmp/gitleaks_8.24.3_linux_x64.tar.gz; \
    curl --fail --location --silent --show-error \
      https://nodejs.org/dist/v22.14.0/node-v22.14.0-linux-x64.tar.xz \
      --output /tmp/node-v22.14.0-linux-x64.tar.xz; \
    printf '%s  %s\n' \
      '69b09dba5c8dcb05c4e4273a4340db1005abeafe3927efda2bc5b249e80437ec' \
      '/tmp/node-v22.14.0-linux-x64.tar.xz' | sha256sum --check --strict; \
    install -d -o jenkins -g jenkins -m 0755 /opt/setness-jenkins/tools/node-v22.14.0-linux-x64 /home/jenkins/agent /home/jenkins/.ssh; \
    tar --extract --xz --file /tmp/node-v22.14.0-linux-x64.tar.xz \
      --directory /opt/setness-jenkins/tools/node-v22.14.0-linux-x64 \
      --strip-components=1; \
    chown -R jenkins:jenkins /opt/setness-jenkins /home/jenkins/agent; \
    rm -f /tmp/node-v22.14.0-linux-x64.tar.xz; \
    apt-get clean

COPY --chown=jenkins:jenkins agent/known_hosts /home/jenkins/.ssh/known_hosts
RUN chmod 0644 /home/jenkins/.ssh/known_hosts

USER jenkins

ENV PATH="/opt/setness-jenkins/tools/node-v22.14.0-linux-x64/bin:${PATH}" \
    JENKINS_AGENT_WORKDIR=/home/jenkins/agent

RUN test "$(node --version)" = "v22.14.0" && test "$(npm --version)" = "10.9.2"

WORKDIR /home/jenkins/agent
