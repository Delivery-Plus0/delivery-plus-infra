# Lint and test everything. Jenkins (infra-ci) and the GitHub workflow run `make lint test` inside
# the tools image (ci/tools.Dockerfile); locally, install the same tools or use `make docker-check`.

TERRAFORM ?= terraform
TF_DIRS := terraform/bootstrap terraform/stacks/platform terraform/stacks/dev
TF_TEST_DIRS := terraform/modules/host terraform/modules/app-storage terraform/modules/ecr terraform/stacks/platform terraform/stacks/dev
SHELL_SCRIPTS := $(wildcard scripts/*.sh tests/*.sh)

.PHONY: lint test tf-lint tf-fmt tf-validate tflint tf-test ansible-lint yamllint shellcheck hadolint python-check \
        compose-test templates-test web-routes-test docker-check clean

lint: tf-lint ansible-lint yamllint shellcheck hadolint python-check
test: tf-test compose-test templates-test web-routes-test

tf-lint: tf-fmt tf-validate tflint

tf-fmt:
	$(TERRAFORM) fmt -check -recursive -diff terraform

tf-validate:
	@set -e; for dir in $(TF_DIRS); do \
	  echo "== validate $$dir"; \
	  $(TERRAFORM) -chdir=$$dir init -backend=false -input=false >/dev/null; \
	  $(TERRAFORM) -chdir=$$dir validate -no-color; \
	done

tflint:
	tflint --init --config "$(CURDIR)/.tflint.hcl"
	tflint --recursive --config "$(CURDIR)/.tflint.hcl" --chdir terraform

# Plan-only tests with fake credentials: no AWS account needed.
tf-test:
	@set -e; for dir in $(TF_TEST_DIRS); do \
	  echo "== test $$dir"; \
	  $(TERRAFORM) -chdir=$$dir init -backend=false -input=false >/dev/null; \
	  $(TERRAFORM) -chdir=$$dir test -no-color; \
	done

ansible-lint:
	cd ansible && ansible-lint
	cd ansible && ANSIBLE_INVENTORY=/dev/null ansible-playbook --syntax-check -i localhost, playbooks/site.yml playbooks/deploy.yml

yamllint:
	yamllint --strict .

shellcheck:
	shellcheck $(SHELL_SCRIPTS)

hadolint:
	hadolint ci/tools.Dockerfile jenkins/controller/Dockerfile

python-check:
	python3 -m py_compile scripts/caddy-routes.py tests/compose_rules.py

# The overlay against the backend compose files (BACKEND_DIR=... for a local checkout, else a clone of BACKEND_REF).
compose-test:
	tests/compose-config.sh

templates-test:
	tests/templates.sh

web-routes-test:
	tests/web-routes.sh

# Everything inside the tools image, as CI runs it.
docker-check:
	docker build -f ci/tools.Dockerfile -t delivery-plus-infra-tools .
	docker run --rm -v "$(CURDIR):/work" -w /work -u "$$(id -u):$$(id -g)" delivery-plus-infra-tools make lint test

clean:
	rm -rf tests/.out
	find terraform -name .terraform -type d -prune -exec rm -rf {} +
