# The Jenkins controller: LTS + the plugins in plugins.txt + the Docker CLI (builds run in containers
# on the host's Docker, through the mounted socket). Configured entirely by JCasC (casc/jenkins.yaml).
FROM jenkins/jenkins:2.479.3-lts-jdk21

USER root

# Docker CLI, Buildx and Compose from Docker's apt repository (the engine stays on the host).
# Unpinned on purpose: the newest Docker CLI that matches the host's engine.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

USER jenkins

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx1g" \
    CASC_JENKINS_CONFIG=/var/jenkins_casc
