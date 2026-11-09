# The shared platform: network, image registry, deploy key, and the Jenkins host.
#
# An admin applies this stack by hand (docs/bootstrap.md): Jenkins runs here, so Jenkins never
# applies the stack it lives in. Jenkins applies the dev stack (terraform/stacks/dev) instead.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  name       = var.project

  # The dev stack's IAM path; Jenkins may manage roles under it, and only under it.
  dev_iam_path = "${var.project}-dev"
}

module "network" {
  source = "../../modules/network"

  name       = local.name
  cidr_block = var.vpc_cidr
}

module "ecr" {
  source = "../../modules/ecr"

  prefix   = var.project
  services = var.services
}

resource "aws_key_pair" "deploy" {
  key_name   = "${local.name}-deploy"
  public_key = var.ssh_public_key
}

# ---------------------------------------------------------------------------------------------
# Jenkins host
# ---------------------------------------------------------------------------------------------

resource "aws_security_group" "jenkins" {
  name        = "${local.name}-jenkins"
  description = "Jenkins: HTTPS UI through Caddy, SSH from admins"
  vpc_id      = module.network.vpc_id

  tags = { Name = "${local.name}-jenkins" }
}

# Let's Encrypt validates over port 80, and the UI is HTTPS on 443 (Jenkins itself listens only on
# the host's loopback behind Caddy, with login required for everything).
resource "aws_vpc_security_group_ingress_rule" "jenkins_http" {
  for_each = toset(["80", "443"])

  security_group_id = aws_security_group.jenkins.id
  description       = "Caddy (TLS for the Jenkins UI)"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.key)
  to_port           = tonumber(each.key)
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_ssh" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.jenkins.id
  description       = "SSH from admins"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.key
}

resource "aws_vpc_security_group_egress_rule" "jenkins_all" {
  security_group_id = aws_security_group.jenkins.id
  description       = "Outbound: GitHub, registries, AWS APIs, SSH to the app host"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

module "jenkins" {
  source = "../../modules/host"

  name               = "${local.name}-jenkins"
  role               = "jenkins"
  instance_type      = var.jenkins_instance_type
  subnet_id          = module.network.public_subnet_id
  security_group_ids = [aws_security_group.jenkins.id]
  key_name           = aws_key_pair.deploy.key_name
  root_volume_size   = var.jenkins_root_volume_size
  data_volume_size   = var.jenkins_data_volume_size
  data_mount_point   = "/var/jenkins_home"
  base_domain        = var.jenkins_base_domain
  iam_path           = "${var.project}-platform"

  tags = {
    Environment = "shared"
    Registry    = module.ecr.registry
    Region      = var.region
    StateBucket = var.state_bucket
  }

  role_policies = {
    ecr-push        = data.aws_iam_policy_document.jenkins_ecr.json
    terraform-state = data.aws_iam_policy_document.jenkins_state.json
    dev-stack       = data.aws_iam_policy_document.jenkins_dev_stack.json
  }
}

# ---------------------------------------------------------------------------------------------
# What Jenkins may do: push images, read/write the dev stack's state, and manage the dev stack.
# ---------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "jenkins_ecr" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = module.ecr.repository_arns
  }
}

data "aws_iam_policy_document" "jenkins_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }

  # The dev stack's state and its lock file.
  statement {
    sid       = "DevState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/dev/*"]
  }

  # The dev stack reads this stack's outputs; Jenkins never writes this stack's state.
  statement {
    sid       = "ReadPlatformState"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/platform/*"]
  }
}

data "aws_iam_policy_document" "jenkins_dev_stack" {
  statement {
    sid       = "Identity"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # EC2 in this region only (instances, volumes, Elastic IPs, security groups, and stop/start).
  statement {
    sid       = "Ec2InRegion"
    actions   = ["ec2:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # IAM for the dev host's role and instance profile, under the dev path only: Jenkins can't touch
  # its own role (under ${var.project}-platform) or anything else in the account.
  statement {
    sid = "DevIam"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:CreateInstanceProfile",
      "iam:CreateRole",
      "iam:DeleteInstanceProfile",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:GetInstanceProfile",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:PassRole",
      "iam:PutRolePolicy",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${local.dev_iam_path}/*",
      "arn:aws:iam::${local.account_id}:instance-profile/${local.dev_iam_path}/*",
    ]
  }

  # The dev buckets (media, documents).
  statement {
    sid     = "DevBuckets"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.project}-dev-*",
      "arn:aws:s3:::${var.project}-dev-*/*",
    ]
  }
}
