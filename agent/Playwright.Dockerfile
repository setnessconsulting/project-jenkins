FROM jenkins/inbound-agent:3355.v388858a_47b_33-14-jdk21@sha256:c3d5dd3c9ca922032daccf8c6226cb877a13b45a4e2e3953c443b4aa9af55e81

USER root

ENV PLAYWRIGHT_VERSION=1.62.1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends ca-certificates curl git openssh-client xz-utils; \
    rm -rf /var/lib/apt/lists/*; \
    curl --fail --location --silent --show-error \
      https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-x64.tar.xz \
      --output /tmp/node-v22.23.3-linux-x64.tar.xz; \
    printf '%s  %s\n' \
      'df450af89261115ef9f9e3830c3eeb2cc9213b63c720b1af623cb5dcbe2e02de' \
      '/tmp/node-v22.23.3-linux-x64.tar.xz' | sha256sum --check --strict; \
    install -d -o jenkins -g jenkins -m 0755 /opt/setness-jenkins/tools/node-v22.23.3-linux-x64 /home/jenkins/agent /home/jenkins/.ssh /opt/ms-playwright; \
    tar --extract --xz --file /tmp/node-v22.23.3-linux-x64.tar.xz \
      --directory /opt/setness-jenkins/tools/node-v22.23.3-linux-x64 \
      --strip-components=1; \
    chown -R jenkins:jenkins /opt/setness-jenkins /home/jenkins/agent; \
    rm -f /tmp/node-v22.23.3-linux-x64.tar.xz; \
    apt-get clean

ENV PATH="/opt/setness-jenkins/tools/node-v22.23.3-linux-x64/bin:${PATH}"

RUN set -eux; \
    npm install --global --ignore-scripts "playwright@${PLAYWRIGHT_VERSION}"; \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright playwright install-deps chromium; \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright playwright install chromium; \
    chmod -R a+rX /opt/ms-playwright; \
    chown -R jenkins:jenkins /home/jenkins/agent /home/jenkins/.ssh

COPY --chown=jenkins:jenkins agent/known_hosts /home/jenkins/.ssh/known_hosts
RUN chmod 0644 /home/jenkins/.ssh/known_hosts

USER jenkins

ENV JENKINS_AGENT_WORKDIR=/home/jenkins/agent

WORKDIR /home/jenkins/agent
