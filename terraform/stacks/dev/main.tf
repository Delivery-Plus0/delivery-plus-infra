# The dev environment: one app host with a static IP (Elastic IP) running the whole backend in Docker
# Compose (Postgres, Redis, Kafka, Zookeeper and the 12 services: nothing AWS-managed), plus the S3
# buckets the backend needs. Jenkins applies this stack (pipelines/terraform.Jenkinsfile).

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "platform/terraform.tfstate"
    region = var.region
  }
}

locals {
  platform   = data.terraform_remote_state.platform.outputs
  account_id = data.aws_caller_identity.current.account_id
  name       = "${var.project}-${var.environment}"

  base_domain = module.app.base_domain
  app_origins = [for host in ["app", "driver", "restaurant"] : "https://${host}.${local.base_domain}"]
}

# ---------------------------------------------------------------------------------------------
# App host security group: the web (Caddy) from anywhere, SSH from admins and from Jenkins.
# Postgres, Redis, Kafka and the services are never published; they're on the Docker network only.
# ---------------------------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "Delivery Plus ${var.environment}: HTTPS via Caddy, SSH from admins and Jenkins"
  vpc_id      = local.platform.vpc_id

  tags = { Name = "${local.name}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "app_web" {
  for_each = {
    http  = { port = 80, protocol = "tcp" }
    https = { port = 443, protocol = "tcp" }
    http3 = { port = 443, protocol = "udp" }
  }

  security_group_id = aws_security_group.app.id
  description       = "Caddy (${each.key})"
  ip_protocol       = each.value.protocol
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh_admins" {
  for_each = toset(local.platform.admin_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "SSH from admins"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.key
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh_jenkins" {
  security_group_id            = aws_security_group.app.id
  description                  = "SSH from Jenkins (Ansible) over the VPC"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = local.platform.jenkins_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound: ECR, S3, Let's Encrypt, OS updates"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------------------------
# Buckets
# ---------------------------------------------------------------------------------------------

module "storage" {
  source = "../../modules/app-storage"

  name                    = local.name
  account_id              = local.account_id
  app_origins             = concat(local.app_origins, var.extra_app_origins)
  document_upload_origins = concat(["https://driver.${local.base_domain}"], var.extra_app_origins)
}

# ---------------------------------------------------------------------------------------------
# App host
# ---------------------------------------------------------------------------------------------

module "app" {
  source = "../../modules/host"

  name               = "${local.name}-app"
  role               = "app"
  instance_type      = var.app_instance_type
  subnet_id          = local.platform.public_subnet_id
  security_group_ids = [aws_security_group.app.id]
  key_name           = local.platform.key_name
  root_volume_size   = var.app_root_volume_size
  data_volume_size   = var.app_data_volume_size
  data_mount_point   = "/srv/data"
  base_domain        = var.base_domain
  iam_path           = local.name

  # Ansible reads these tags (inventory/aws_ec2.yml), so the host's configuration has one source.
  tags = {
    Environment     = var.environment
    Region          = var.region
    Registry        = local.platform.ecr_registry
    MediaBucket     = module.storage.media_bucket
    DocumentsBucket = module.storage.documents_bucket
    MediaBaseUrl    = module.storage.media_public_base_url
    ExtraOrigins    = join(" ", var.extra_app_origins)
    SesFromAddress  = var.enable_ses ? var.ses_from_address : ""
  }

  role_policies = merge(
    {
      s3       = module.storage.app_access_policy_json
      ecr-pull = data.aws_iam_policy_document.ecr_pull.json
    },
    var.enable_ses ? { ses = data.aws_iam_policy_document.ses.json } : {},
  )
}

data "aws_iam_policy_document" "ecr_pull" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = local.platform.ecr_repository_arns
  }
}

# Only from the configured sender (auth-service's verification codes, backend #203).
data "aws_iam_policy_document" "ses" {
  statement {
    sid       = "SendFromSender"
    actions   = ["ses:SendEmail"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.ses_from_address]
    }
  }
}

check "ses_sender" {
  assert {
    condition     = !var.enable_ses || var.ses_from_address != ""
    error_message = "enable_ses needs ses_from_address (a verified SES identity)."
  }
}
