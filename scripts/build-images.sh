#!/usr/bin/env bash
# Builds the backend's 12 service images from one checkout and pushes them to ECR, tagged with the
# commit. A tag that already exists in ECR is skipped (tags are immutable: same tag, same code).
#
#   ECR_REGISTRY=... IMAGE_TAG=0123456789ab scripts/build-images.sh path/to/delivery-plus
set -euo pipefail

src="${1:?usage: build-images.sh <backend checkout>}"
: "${ECR_REGISTRY:?ECR_REGISTRY must be set}"
: "${IMAGE_TAG:?IMAGE_TAG must be set}"
: "${AWS_REGION:?AWS_REGION must be set}"
prefix="${ECR_PREFIX:-delivery-plus}"
services=(
  api-gateway auth-service user-service restaurant-service menu-service cart-service
  order-service payment-service delivery-service driver-service tracking-service notification-service
)

[[ -f "${src}/Dockerfile" ]] || { echo "No Dockerfile in ${src}" >&2; exit 2; }

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null

export DOCKER_BUILDKIT=1
built=0
for service in "${services[@]}"; do
  image="${ECR_REGISTRY}/${prefix}/${service}:${IMAGE_TAG}"
  if aws ecr describe-images --region "$AWS_REGION" --repository-name "${prefix}/${service}" \
       --image-ids "imageTag=${IMAGE_TAG}" >/dev/null 2>&1; then
    echo "== ${service}: ${IMAGE_TAG} is already in ECR, skipped"
    continue
  fi
  echo "== ${service}: building ${image}"
  # The builder stage is the same for every service (BuildKit caches it), so only the first build is slow.
  docker build \
    --build-arg "SERVICE_NAME=${service}" \
    --label "org.opencontainers.image.revision=${IMAGE_TAG}" \
    --label "org.opencontainers.image.source=https://github.com/Delivery-Plus0/delivery-plus" \
    --tag "$image" \
    "$src"
  docker push "$image"
  docker image rm "$image" >/dev/null
  built=$((built + 1))
done

echo "Built and pushed ${built} image(s) for ${IMAGE_TAG}."
