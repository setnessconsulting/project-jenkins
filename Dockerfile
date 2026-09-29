FROM jenkins/jenkins:2.568.3-jdk21@sha256:c1e4c349365f6d16d88595b2c5f7e8ff39b8ae1d061f62420bac193b4b9616d0

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --latest=false

# Trusted Test Platform consumer adapter (API-390): install the pinned Node 22
# runtime as root into a Jenkins-owned tool directory, then return to the
# unprivileged Jenkins user. The adapter has no npm dependencies and never
# resolves a credential.
USER root

RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends ca-certificates curl xz-utils; \
    rm -rf /var/lib/apt/lists/*; \
    curl --fail --location --silent --show-error \
      https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-x64.tar.xz \
      --output /tmp/node-v22.23.3-linux-x64.tar.xz; \
    printf '%s  %s\n' \
      'df450af89261115ef9f9e3830c3eeb2cc9213b63c720b1af623cb5dcbe2e02de' \
      '/tmp/node-v22.23.3-linux-x64.tar.xz' | sha256sum --check --strict; \
    install -d -o jenkins -g jenkins -m 0755 /opt/setness-jenkins/tools/node-v22.23.3-linux-x64; \
    tar --extract --xz --file /tmp/node-v22.23.3-linux-x64.tar.xz \
      --directory /opt/setness-jenkins/tools/node-v22.23.3-linux-x64 \
      --strip-components=1; \
    chown -R jenkins:jenkins /opt/setness-jenkins; \
    rm -f /tmp/node-v22.23.3-linux-x64.tar.xz; \
    apt-get clean

COPY --chown=jenkins:jenkins integration/test-platform-contract /usr/share/jenkins/test-platform-contract
COPY --chown=jenkins:jenkins integration/portfolio-profile-contract /usr/share/jenkins/portfolio-profile-contract

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml \
    PATH="/opt/setness-jenkins/tools/node-v22.23.3-linux-x64/bin:${PATH}"

USER jenkins

RUN node --version
