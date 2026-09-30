FROM jenkins/inbound-agent:3355.v388858a_47b_33-14-jdk21@sha256:c3d5dd3c9ca922032daccf8c6226cb877a13b45a4e2e3953c443b4aa9af55e81 AS python-builder

USER root

ARG PYTHON_VERSION=3.12.14
ARG PYTHON_SOURCE_SHA256=5c8462af5790baf43a321a1559dbe0db06d1be4300fb85fb53c40060668e548a

RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends \
      build-essential ca-certificates curl xz-utils \
      libbz2-dev libexpat1-dev libffi-dev libgdbm-dev liblzma-dev \
      libncurses-dev libreadline-dev libsqlite3-dev libssl-dev uuid-dev zlib1g-dev; \
    rm -rf /var/lib/apt/lists/*; \
    curl --fail --location --silent --show-error \
      "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" \
      --output "/tmp/Python-${PYTHON_VERSION}.tar.xz"; \
    printf '%s  %s\n' "$PYTHON_SOURCE_SHA256" "/tmp/Python-${PYTHON_VERSION}.tar.xz" | sha256sum --check --strict; \
    tar --extract --xz --file "/tmp/Python-${PYTHON_VERSION}.tar.xz" --directory /tmp; \
    cd "/tmp/Python-${PYTHON_VERSION}"; \
    ./configure --prefix="/opt/setness-jenkins/python-${PYTHON_VERSION}" --enable-shared --with-ensurepip=install; \
    make -j"$(nproc)"; \
    make install; \
    ln -s "python${PYTHON_VERSION%.*}" "/opt/setness-jenkins/python-${PYTHON_VERSION}/bin/python"; \
    LD_LIBRARY_PATH="/opt/setness-jenkins/python-${PYTHON_VERSION}/lib" \
      "/opt/setness-jenkins/python-${PYTHON_VERSION}/bin/python" --version; \
    rm -rf "/tmp/Python-${PYTHON_VERSION}" "/tmp/Python-${PYTHON_VERSION}.tar.xz"

FROM jenkins/inbound-agent:3355.v388858a_47b_33-14-jdk21@sha256:c3d5dd3c9ca922032daccf8c6226cb877a13b45a4e2e3953c443b4aa9af55e81

USER root

ARG PYTHON_VERSION=3.12.14

RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends \
      ca-certificates libbz2-1.0 libexpat1 libffi8 libgdbm6t64 liblzma5 libncursesw6 \
      libreadline8 libsqlite3-0 libssl3t64 libuuid1 zlib1g; \
    rm -rf /var/lib/apt/lists/*; \
    install -d -o jenkins -g jenkins -m 0755 /home/jenkins/agent

COPY --from=python-builder --chown=jenkins:jenkins \
  /opt/setness-jenkins/python-3.12.14 /opt/setness-jenkins/python-3.12.14

ENV PATH="/opt/setness-jenkins/python-3.12.14/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/setness-jenkins/python-3.12.14/lib" \
    JENKINS_AGENT_WORKDIR=/home/jenkins/agent

USER jenkins

RUN test "$(python --version)" = "Python ${PYTHON_VERSION}" \
    && python -c "import bz2, ctypes, lzma, readline, sqlite3, ssl, zlib"

WORKDIR /home/jenkins/agent
