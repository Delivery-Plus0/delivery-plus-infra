#!/usr/bin/env bash
# scripts/caddy-routes.py against a miniature Expo static export, served by a real Caddy with the
# same directives as the app host's Caddyfile: deep links to dynamic routes get their page, static
# routes their .html file, and anything else the app's index.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
port="${WEB_ROUTES_PORT:-18080}"
cleanup() { [[ -n "${caddy_pid:-}" ]] && kill "$caddy_pid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

site="${work}/site"
mkdir -p "${site}/order" "${site}/restaurant" "${site}/(app)/order" "${site}/_expo/static/js"
echo 'INDEX' > "${site}/index.html"
echo 'HOME' > "${site}/home.html"
echo 'ORDER' > "${site}/order/[id].html"
echo 'GROUPED' > "${site}/(app)/order/[id].html"
echo 'RESTAURANT' > "${site}/restaurant/[id].html"
echo 'console.log(1)' > "${site}/_expo/static/js/app.js"

python3 "${root}/scripts/caddy-routes.py" "$site" > "${work}/routes.caddy"
if grep -q '(app)' "${work}/routes.caddy"; then
  echo "Route groups must not get rules (Expo writes flattened copies)"; exit 1
fi

cat > "${work}/Caddyfile" <<CADDY
{
	admin off
	auto_https off
}
http://127.0.0.1:${port} {
	root * ${site}
	import ${work}/routes.caddy
	try_files {path} {path}.html {path}/index.html /index.html
	file_server
}
CADDY
caddy run --adapter caddyfile --config "${work}/Caddyfile" >"${work}/caddy.log" 2>&1 &
caddy_pid=$!
for _ in $(seq 1 50); do curl -fs "http://127.0.0.1:${port}/" >/dev/null 2>&1 && break; sleep 0.1; done

failures=0
check() {
  local path="$1" want="$2" got
  got=$(curl -fs "http://127.0.0.1:${port}${path}" || echo "HTTP-ERROR")
  if [[ "$got" == "$want" ]]; then echo "  ok    ${path} -> ${want}"; else echo "  FAIL  ${path}: got '${got}', want '${want}'"; failures=$((failures + 1)); fi
}
check /order/3f2a9c1e-0000-4000-8000-000000000001 ORDER
check /order/abc/ ORDER
check /restaurant/42 RESTAURANT
check /home HOME
check / INDEX
check /no/such/page INDEX
check /_expo/static/js/app.js 'console.log(1)'

if (( failures > 0 )); then cat "${work}/caddy.log"; exit 1; fi
echo "Web routes OK."
