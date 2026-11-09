#!/usr/bin/env bash
# Checks a deployed environment from the outside, the way clients reach it:
#   - the API answers over HTTPS with a valid certificate, and over the bare static IP;
#   - the gateway reports healthy, and a public endpoint returns data;
#   - CORS lets the customer app's origin call the API;
#   - each web app answers, including a deep link to a dynamic route.
#
#   BASE_DOMAIN=203-0-113-10.sslip.io PUBLIC_IP=203.0.113.10 scripts/smoke-test.sh [--skip-web]
set -euo pipefail

: "${BASE_DOMAIN:?BASE_DOMAIN must be set}"
: "${PUBLIC_IP:?PUBLIC_IP must be set}"
api="https://api.${BASE_DOMAIN}"
skip_web=false
[[ "${1:-}" == "--skip-web" ]] && skip_web=true

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
# expect <actual> <wanted> <label on success> <label on failure>
expect() { if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$4"; fi; }

# Let's Encrypt can take a minute on a first deploy; retry the first request.
status_of() { curl --silent --output /dev/null --write-out '%{http_code}' --max-time 15 "$@" || echo 000; }

echo "API ${api}"
for attempt in $(seq 1 12); do
  code=$(status_of "${api}/health")
  [[ "$code" == 200 ]] && break
  echo "  waiting for ${api}/health (HTTP ${code}, attempt ${attempt}/12)"
  sleep 10
done
expect "$code" 200 "GET /health over HTTPS (valid certificate)" "GET /health over HTTPS: HTTP ${code}"

code=$(status_of "http://${PUBLIC_IP}/health")
expect "$code" 200 "GET /health on the static IP (http://${PUBLIC_IP})" "GET http://${PUBLIC_IP}/health: HTTP ${code}"

body=$(curl --silent --max-time 15 "${api}/api/restaurants?page=1&limit=1" || true)
if jq -e '.items | type == "array"' >/dev/null 2>&1 <<<"$body"; then
  pass "GET /api/restaurants returns a list (services, Postgres and Redis answer)"
else
  fail "GET /api/restaurants: ${body:0:200}"
fi

origin="https://app.${BASE_DOMAIN}"
allowed=$(curl --silent --max-time 15 --output /dev/null --dump-header - -X OPTIONS \
  -H "Origin: ${origin}" -H 'Access-Control-Request-Method: GET' "${api}/api/restaurants" \
  | tr -d '\r' | awk -F': ' 'tolower($1) == "access-control-allow-origin" { print $2 }')
expect "$allowed" "$origin" "CORS allows ${origin}" "CORS for ${origin}: got '${allowed}'"

if [[ "$skip_web" == false ]]; then
  echo "Web apps"
  for host in app driver restaurant; do
    code=$(status_of "https://${host}.${BASE_DOMAIN}/")
    expect "$code" 200 "https://${host}.${BASE_DOMAIN}/" "https://${host}.${BASE_DOMAIN}/: HTTP ${code}"
  done
  # A deep link to a dynamic route is served its page, not a 404 (scripts/caddy-routes.py).
  code=$(status_of "https://app.${BASE_DOMAIN}/order/00000000-0000-0000-0000-000000000000")
  expect "$code" 200 "deep link /order/<id> on the customer app" "deep link /order/<id>: HTTP ${code}"
fi

if (( failures > 0 )); then
  echo "${failures} check(s) failed."
  exit 1
fi
echo "All checks passed."
