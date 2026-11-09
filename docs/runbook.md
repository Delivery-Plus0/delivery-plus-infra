# Runbook

All commands on the app host run as root through `dp-compose`, which wraps `docker compose` with this host's files and environment. Log in with:

```bash
ssh -i ~/.ssh/delivery-plus-deploy ubuntu@<static ip>
```

The login banner shows the URLs and the deployed commit.

## Everyday

| Task | Command |
| --- | --- |
| What's running and healthy | `sudo dp-compose ps` |
| Follow a service's logs | `sudo dp-compose logs -f --tail 200 order-service` |
| Restart one service | `sudo dp-compose restart payment-service` |
| The deployed commit | `cat /opt/delivery-plus/release.env`; history in `/opt/delivery-plus/releases.log` |
| Disk usage | `df -h / /srv/data`; `sudo docker system df` |
| A psql shell | `sudo dp-compose exec postgres psql -U delivery_plus -d order_service` |
| Redis | `sudo dp-compose exec redis redis-cli` |
| Kafka topics | `sudo dp-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --describe` |
| Dead letters | `sudo dp-compose exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic order.events.dlq --from-beginning --max-messages 10` |

## Kafka UI and other local-only tools

Kafka UI listens only on the host's loopback. Start it, then tunnel to it:

```bash
ssh ubuntu@<static ip> sudo dp-compose --profile tools up -d kafka-ui
ssh -N -L 8085:127.0.0.1:8085 -i ~/.ssh/delivery-plus-deploy ubuntu@<static ip>
# open http://localhost:8085
```

The same tunnel works for Postgres, for example with a desktop client. Publish nothing new instead: the security group allows only 80/443.

## Deploying and rolling back

- **Deploy:** run `dev-deploy` with `BACKEND_REF` set to a branch, tag or commit.
- **Roll back:** run `dev-deploy` with the previous commit (from `releases.log`). Images still in ECR (the newest 15 per service) aren't rebuilt.
- **Migrations** are forward-only. If the newer release migrated a database, the older code may not run on it. Fix forward, or restore a backup.

## Saving money

Run `dev-power` with `ACTION=stop` in the evening and `ACTION=start` in the morning. The static IP, the data volume and the buckets stay; Docker starts the stack on boot. While stopped, you pay only for the EBS volumes and the Elastic IP.

Rough on-demand cost in `eu-central-1`, before tax, running all month. Check current AWS prices before relying on these numbers.

| Item | ≈ per month |
| --- | --- |
| App host t3.large | $70 |
| Jenkins host t3.medium | $35 |
| EBS gp3: 40 + 50 GiB (app), 50 + 40 GiB (Jenkins) | $17 |
| 2 public IPv4 addresses | $7 |
| ECR, S3, data transfer | a few dollars |

## TLS certificates

Caddy gets and renews the certificates itself and keeps them in `/srv/data/caddy`. If a site has no certificate:
- check that ports 80 and 443 are reachable from the internet (the security group);
- check `sudo dp-compose logs edge`;
- check that the name resolves to the static IP (`dig +short api.<ip-with-dashes>.sslip.io`).

`sslip.io` is a shared domain, and Let's Encrypt limits certificates per registered domain. If you hit those limits, use your own domain (`base_domain` in the dev stack).

## Rotating a secret

Secrets live in `/srv/data/secrets/<NAME>`. Delete the file and run `dev-ansible` (check mode off) to generate a new one; the stack restarts with it. What each rotation does:

| Secret | Effect of rotating it |
| --- | --- |
| `JWT_SECRET` | Every user is signed out (tokens no longer verify). |
| `SYSTEM_JWT_SECRET`, `INTERNAL_AUTH_SECRET` | Service-to-service calls use the new value after the restart; harmless. |
| `EMAIL_CODE_HASH_SECRET`, `OTP_HASH_SECRET` | Codes already sent stop working. |
| `NATIONAL_ID_HMAC_SECRET` | **Don't rotate it.** Existing hashes stop matching, so the duplicate-ID check misses old drivers (backend #207). |
| `POSTGRES_PASSWORD` | **Don't just delete it.** Postgres keeps the old password in its data directory. First change it inside Postgres (`ALTER USER delivery_plus PASSWORD '...'`), then write the same value to the file. |

## Backups

The dev environment has no automatic backups. For a point to return to before a risky change, snapshot the data volume:

```bash
aws ec2 create-snapshot --volume-id "$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=delivery-plus-dev-app --query 'Reservations[0].Instances[0].Tags[?Key==`DataVolumeId`]|[0].Value' --output text)" \
  --description "delivery-plus dev before <change>"
```

For a consistent copy, stop the stack first (`sudo dp-compose stop`).

## Replacing the app host

For a new AMI, a corrupted OS or a resize: `terraform apply -replace=module.app.aws_instance.this` from `dev-terraform` (or locally), then `dev-ansible` and `dev-deploy`. The data volume is detached and re-attached, and the static IP moves to the new instance.

## Tearing it down

Run `dev-terraform` with `ACTION=destroy` and `CONFIRM_DESTROY=delivery-plus-dev`. This deletes the app host, its data, the static IP and both buckets. The platform stack (Jenkins, ECR, network) is destroyed only by hand:

```bash
terraform -chdir=terraform/stacks/platform destroy
```
