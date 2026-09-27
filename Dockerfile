FROM jenkins/jenkins:2.568.3-jdk21@sha256:c1e4c349365f6d16d88595b2c5f7e8ff39b8ae1d061f62420bac193b4b9616d0

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --latest=false

# Trusted Test Platform consumer adapter (API-390): the pinned Node 22
# runtime and the centrally maintained adapter are controller-local. The
# adapter has no npm dependencies and never resolves a credential.
RUN curl -fsSL https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-x64.tar.xz -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && node --version
COPY --chown=jenkins:jenkins integration/test-platform-contract /usr/share/jenkins/test-platform-contract

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml
