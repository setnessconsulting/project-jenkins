FROM jenkins/inbound-agent:3355.v388858a_47b_33-14-jdk21@sha256:c3d5dd3c9ca922032daccf8c6226cb877a13b45a4e2e3953c443b4aa9af55e81

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends ca-certificates curl git openssh-client xz-utils; \
    rm -rf /var/lib/apt/lists/*; \
    curl --fail --location --silent --show-error \
      https://nodejs.org/dist/v24.21.0/node-v24.21.0-linux-x64.tar.xz \
      --output /tmp/node-v24.21.0-linux-x64.tar.xz; \
    printf '%s  %s\n' \
      'fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6' \
      '/tmp/node-v24.21.0-linux-x64.tar.xz' | sha256sum --check --strict; \
    install -d -o jenkins -g jenkins -m 0755 /opt/setness-jenkins/tools/node-v24.21.0-linux-x64 /home/jenkins/agent /home/jenkins/.ssh; \
    tar --extract --xz --file /tmp/node-v24.21.0-linux-x64.tar.xz \
      --directory /opt/setness-jenkins/tools/node-v24.21.0-linux-x64 \
      --strip-components=1; \
    chown -R jenkins:jenkins /opt/setness-jenkins /home/jenkins/agent; \
    rm -f /tmp/node-v24.21.0-linux-x64.tar.xz; \
    apt-get clean

COPY --chown=jenkins:jenkins agent/known_hosts /home/jenkins/.ssh/known_hosts
RUN chmod 0644 /home/jenkins/.ssh/known_hosts

USER jenkins

ENV PATH="/opt/setness-jenkins/tools/node-v24.21.0-linux-x64/bin:${PATH}" \
    JENKINS_AGENT_WORKDIR=/home/jenkins/agent

WORKDIR /home/jenkins/agent
