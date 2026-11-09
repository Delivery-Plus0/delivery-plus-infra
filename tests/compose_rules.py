#!/usr/bin/env python3
"""Rules for the merged compose config of the dev host (docker compose config --format json)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

APP_SERVICES = {
    "api-gateway", "auth-service", "user-service", "restaurant-service", "menu-service", "cart-service",
    "order-service", "payment-service", "delivery-service", "driver-service", "tracking-service",
    "notification-service",
}
INFRA = {"postgres", "redis", "zookeeper", "kafka"}


def load_env(path: Path) -> dict[str, str]:
    values = {}
    for line in path.read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


def main(config_path: str, env_path: str) -> int:
    config = json.loads(Path(config_path).read_text())
    env = load_env(Path(env_path))
    services = config["services"]
    problems: list[str] = []

    missing = (APP_SERVICES | INFRA | {"edge", "kafka-init", "kafka-ui"}) - services.keys()
    if missing:
        problems.append(f"services missing: {sorted(missing)}")

    registry, tag = env["ECR_REGISTRY"], env["IMAGE_TAG"]
    for name in APP_SERVICES & services.keys():
        image = services[name].get("image", "")
        if image != f"{registry}/delivery-plus/{name}:{tag}":
            problems.append(f"{name}: image {image!r} is not the ECR image for the release")
        if "mem_limit" not in services[name]:
            problems.append(f"{name}: no memory limit")

    # Only Caddy is public; Kafka UI only on the host's loopback.
    for name, service in services.items():
        for port in service.get("ports", []):
            published, host_ip = str(port.get("published", "")), port.get("host_ip", "")
            if name == "edge" and published in {"80", "443"}:
                continue
            if name == "kafka-ui" and host_ip == "127.0.0.1":
                continue
            problems.append(f"{name}: publishes {host_ip or '0.0.0.0'}:{published}")

    # No static AWS keys anywhere: S3 uses the instance role.
    for name, service in services.items():
        environment = service.get("environment") or {}
        for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
            if environment.get(key):
                problems.append(f"{name}: {key} is set; S3 must use the instance role")

    # Stateful data lives on the data volume.
    data_dir = env["DATA_DIR"]
    for volume in ("postgres_data", "redis_data", "kafka_data", "zookeeper_data", "zookeeper_log"):
        device = (config.get("volumes", {}).get(volume, {}).get("driver_opts") or {}).get("device", "")
        if not device.startswith(data_dir + "/"):
            problems.append(f"volume {volume}: not bound under {data_dir} (device {device!r})")

    kafka_env = services.get("kafka", {}).get("environment") or {}
    if "Xmx" not in kafka_env.get("KAFKA_HEAP_OPTS", ""):
        problems.append("kafka: no heap limit")

    gateway_env = services.get("api-gateway", {}).get("environment") or {}
    if gateway_env.get("TRUSTED_PROXY_HOPS") != "1":
        problems.append("api-gateway: TRUSTED_PROXY_HOPS must be 1 behind Caddy")

    if problems:
        print("Compose rules failed:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print(f"Compose config OK: {len(services)} services, images {registry}/delivery-plus/*:{tag}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
