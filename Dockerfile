FROM jenkins/jenkins:2.568.3-jdk21@sha256:c1e4c349365f6d16d88595b2c5f7e8ff39b8ae1d061f62420bac193b4b9616d0

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --latest=false

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml
