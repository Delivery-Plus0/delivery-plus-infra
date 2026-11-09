#!/usr/bin/env bash
# terraform init for a stack against the S3 state bucket, from the environment (Jenkins sets
# STATE_BUCKET and AWS_REGION globally).
#
#   scripts/tf-init.sh dev        # terraform/stacks/dev, state key dev/terraform.tfstate
set -euo pipefail

stack="${1:?usage: tf-init.sh <stack>}"
dir="terraform/stacks/${stack}"
[[ -d "$dir" ]] || { echo "No stack at $dir" >&2; exit 2; }
: "${STATE_BUCKET:?STATE_BUCKET must be set (the bucket from terraform/bootstrap)}"
: "${AWS_REGION:?AWS_REGION must be set}"

cat > "${dir}/backend.hcl" <<HCL
bucket       = "${STATE_BUCKET}"
key          = "${stack}/terraform.tfstate"
region       = "${AWS_REGION}"
encrypt      = true
use_lockfile = true
HCL

"${TERRAFORM:-terraform}" -chdir="$dir" init -input=false -reconfigure -backend-config=backend.hcl
