# The tools every pipeline uses (Jenkins agents and the GitHub workflow): Terraform, TFLint,
# Ansible (with the amazon.aws / community.* collections), the AWS CLI, Docker CLI with Buildx and
# Compose, Caddy (config validation), ShellCheck, Hadolint, yamllint.
FROM python:3.12-slim-bookworm

ARG TERRAFORM_VERSION=1.10.5
ARG TFLINT_VERSION=0.53.0
ARG SHELLCHECK_VERSION=0.10.0
ARG HADOLINT_VERSION=2.12.0
ARG CADDY_VERSION=2.8.4
ARG DOCKER_VERSION=27.3.1
ARG BUILDX_VERSION=0.17.1
ARG COMPOSE_VERSION=2.29.7

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git jq make openssh-client rsync unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && unzip -q /tmp/terraform.zip terraform -d /usr/local/bin \
    && curl -fsSL -o /tmp/tflint.zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
    && unzip -q /tmp/tflint.zip -d /usr/local/bin \
    && curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
       | tar -xJ --strip-components=1 -C /usr/local/bin "shellcheck-v${SHELLCHECK_VERSION}/shellcheck" \
    && curl -fsSL -o /usr/local/bin/hadolint "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64" \
    && curl -fsSL "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" \
       | tar -xz -C /usr/local/bin caddy \
    && curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
       | tar -xz --strip-components=1 -C /usr/local/bin docker/docker \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-buildx "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64" \
    && curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    && chmod +x /usr/local/bin/* /usr/local/lib/docker/cli-plugins/* \
    && rm -f /tmp/*.zip

COPY ci/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Pipelines run as the Jenkins uid (1000), which has no home in this image.
ENV HOME=/home/tools \
    ANSIBLE_HOME=/home/tools/.ansible \
    TF_PLUGIN_CACHE_DIR=/home/tools/.terraform.d/plugin-cache
RUN mkdir -p /home/tools/.terraform.d/plugin-cache && chmod -R 1777 /home/tools

WORKDIR /work
