#!/usr/bin/env bash
# Prints the running dev app host's settings as KEY=value lines, from its tags:
#   INSTANCE_ID, PUBLIC_IP, PRIVATE_IP, BASE_DOMAIN, API_URL
#
#   eval "$(scripts/env-info.sh)"
set -euo pipefail

environment="${ENVIRONMENT:-dev}"
# JMESPath literals use backticks; nothing here is meant to expand.
# shellcheck disable=SC2016
query='Reservations[].Instances[] | [0].[InstanceId, PrivateIpAddress, Tags[?Key==`PublicIp`]|[0].Value, Tags[?Key==`BaseDomain`]|[0].Value, State.Name]'

read -r instance private_ip public_ip base_domain state < <(
  aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=delivery-plus" "Name=tag:Environment,Values=${environment}" \
              "Name=tag:Role,Values=app" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "$query" --output text
)

if [[ -z "${instance:-}" || "$instance" == "None" ]]; then
  echo "No ${environment} app host found. Apply the ${environment} stack first (dev-terraform)." >&2
  exit 1
fi

echo "INSTANCE_ID=${instance}"
echo "INSTANCE_STATE=${state}"
echo "PUBLIC_IP=${public_ip}"
echo "PRIVATE_IP=${private_ip}"
echo "BASE_DOMAIN=${base_domain}"
echo "API_URL=https://api.${base_domain}"
