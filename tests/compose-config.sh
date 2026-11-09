#!/usr/bin/env bash
# The compose overlay against the backend's real compose files: it must merge without errors, with
# only the variables the host's .env/release.env provide (tests/fixtures/compose.env), and keep the
# rules this environment depends on (see tests/compose_rules.py).
#
#   BACKEND_DIR=../delivery-plus tests/compose-config.sh     # a local checkout
#   BACKEND_REF=dev tests/compose-config.sh                  # or a fresh shallow clone
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [[ -n "${BACKEND_DIR:-}" ]]; then
  backend="$(cd "$BACKEND_DIR" && pwd)"
else
  backend="${work}/backend"
  git clone --quiet --depth 1 --branch "${BACKEND_REF:-dev}" https://github.com/Delivery-Plus0/delivery-plus.git "$backend"
fi

mkdir -p "${work}/stack/docker/postgres"
cp "${backend}/docker-compose.base.yml" "${backend}/docker-compose.prod.yml" "${work}/stack/"
cp "${backend}/docker/postgres/init.sql" "${work}/stack/docker/postgres/"
cp "${root}/compose/docker-compose.ec2.yml" "${work}/stack/"

# A clean environment: nothing from the caller's shell (AWS keys, say) may satisfy the files.
env -i PATH="$PATH" HOME="$work" docker compose \
  --project-directory "${work}/stack" --project-name delivery-plus \
  --env-file "${root}/tests/fixtures/compose.env" \
  -f "${work}/stack/docker-compose.base.yml" \
  -f "${work}/stack/docker-compose.prod.yml" \
  -f "${work}/stack/docker-compose.ec2.yml" \
  --profile init --profile tools \
  config --format json > "${work}/config.json"

python3 "${root}/tests/compose_rules.py" "${work}/config.json" "${root}/tests/fixtures/compose.env"
