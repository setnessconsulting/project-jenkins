FROM jenkins/inbound-agent:3355.v388858a_47b_33-14-jdk21@sha256:c3d5dd3c9ca922032daccf8c6226cb877a13b45a4e2e3953c443b4aa9af55e81

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends ca-certificates curl git xz-utils; \
    curl --fail --location --silent --show-error \
      https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/powershell-lts_7.6.6-1.deb_amd64.deb \
      --output /tmp/powershell-lts_7.6.6-1.deb_amd64.deb; \
    printf '%s  %s\n' \
      '40445854085082B23624D7E437EF17D89DD9C67A72895843297EEAFD5D0163DE' \
      '/tmp/powershell-lts_7.6.6-1.deb_amd64.deb' | sha256sum --check --strict; \
    apt-get install --yes /tmp/powershell-lts_7.6.6-1.deb_amd64.deb; \
    curl --fail --location --silent --show-error \
      https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-x64.tar.xz \
      --output /tmp/node-v22.23.3-linux-x64.tar.xz; \
    printf '%s  %s\n' \
      'df450af89261115ef9f9e3830c3eeb2cc9213b63c720b1af623cb5dcbe2e02de' \
      '/tmp/node-v22.23.3-linux-x64.tar.xz' | sha256sum --check --strict; \
    install -d -o jenkins -g jenkins -m 0755 /opt/setness-jenkins/tools/node-v22.23.3-linux-x64 /home/jenkins/agent; \
    tar --extract --xz --file /tmp/node-v22.23.3-linux-x64.tar.xz \
      --directory /opt/setness-jenkins/tools/node-v22.23.3-linux-x64 \
      --strip-components=1; \
    chown -R jenkins:jenkins /opt/setness-jenkins /home/jenkins/agent; \
    rm -f /tmp/node-v22.23.3-linux-x64.tar.xz /tmp/powershell-lts_7.6.6-1.deb_amd64.deb; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get clean

USER jenkins

ENV PATH="/opt/setness-jenkins/tools/node-v22.23.3-linux-x64/bin:${PATH}" \
    JENKINS_AGENT_WORKDIR=/home/jenkins/agent

RUN test "$(node --version)" = "v22.23.3" && \
    test "$(npm --version)" = "10.9.9" && \
    test "$(pwsh --version)" = "PowerShell 7.6.6"

WORKDIR /home/jenkins/agent
