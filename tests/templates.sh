#!/usr/bin/env bash
# Renders the Ansible templates with fixtures (tests/templates.yml), then checks each with the tool
# that will read it: Caddy for the Caddyfiles, docker compose for compose files and the .env, a YAML
# parser for JCasC, bash and shellcheck for the scripts.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${root}/tests/.out"
rm -rf "$out"

ANSIBLE_CONFIG="${root}/ansible/ansible.cfg" ANSIBLE_ROLES_PATH="${root}/ansible/roles" \
  ansible-playbook -i localhost, "${root}/tests/templates.yml" >/dev/null

# Routes for the Caddyfile's imports, as a web deploy would write them.
for app in customer driver restaurant; do
  printf '@route0 path_regexp ^/order/[^/?#]+/?$\nrewrite @route0 "/order/[id].html"\n' > "${out}/routes/${app}.caddy"
done

echo "Caddy: app host and Jenkins configurations"
caddy validate --adapter caddyfile --config "${out}/app/Caddyfile" >/dev/null 2>&1 \
  || caddy validate --adapter caddyfile --config "${out}/app/Caddyfile"
caddy validate --adapter caddyfile --config "${out}/jenkins/Caddyfile" >/dev/null 2>&1 \
  || caddy validate --adapter caddyfile --config "${out}/jenkins/Caddyfile"
caddy fmt "${out}/app/Caddyfile" | diff -q - "${out}/app/Caddyfile" >/dev/null \
  || { echo "The app Caddyfile isn't caddy-fmt formatted:"; caddy fmt "${out}/app/Caddyfile" | diff - "${out}/app/Caddyfile"; exit 1; }

echo "The .env defines everything the compose files need"
fixture_keys=$(grep -Ev '^\s*(#|$)' "${root}/tests/fixtures/compose.env" | cut -d= -f1 | grep -Ev '^IMAGE_TAG$' | sort)
env_keys=$(grep -Ev '^\s*(#|$)' "${out}/app/.env" | cut -d= -f1 | sort)
missing=$(comm -23 <(echo "$fixture_keys") <(echo "$env_keys"))
[[ -z "$missing" ]] || { echo "The .env template misses: ${missing}"; exit 1; }
grep -q '^CORS_ORIGINS=https://app.203-0-113-10.sslip.io,https://driver.203-0-113-10.sslip.io,https://restaurant.203-0-113-10.sslip.io,http://localhost:8081$' "${out}/app/.env" \
  || { echo "CORS_ORIGINS isn't the three apps plus the extra origins"; grep CORS "${out}/app/.env"; exit 1; }
if grep -Eq '^AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)=' "${out}/app/.env"; then
  echo "The .env must not carry AWS keys (S3 uses the instance role)"; exit 1
fi

echo "Jenkins: JCasC is YAML, the compose file is valid"
python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "${out}/jenkins/jenkins.yaml"
env -i PATH="$PATH" HOME="$out" docker compose -f "${out}/jenkins/docker-compose.yml" config --quiet

echo "Scripts"
bash -n "${out}/app/dp-compose" "${out}/app/motd"
shellcheck "${out}/app/dp-compose" "${out}/app/motd"

echo "Templates OK."
