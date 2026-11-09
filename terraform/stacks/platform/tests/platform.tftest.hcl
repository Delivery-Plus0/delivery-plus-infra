# Plan-only tests with the real AWS provider and fake credentials: no AWS account or network needed.

provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_data {
  target = module.network.data.aws_availability_zones.available
  values = { names = ["eu-central-1a", "eu-central-1b"] }
}

override_data {
  target = module.jenkins.data.aws_ami.ubuntu
  values = { id = "ami-0123456789abcdef0" }
}

override_data {
  target = module.jenkins.data.aws_subnet.this
  values = { availability_zone = "eu-central-1a" }
}

variables {
  state_bucket   = "delivery-plus-tfstate-123456789012"
  admin_cidrs    = ["198.51.100.7/32"]
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnly delivery-plus-deploy"
}

run "ssh_only_from_admins" {
  command = plan

  assert {
    condition     = toset([for rule in aws_vpc_security_group_ingress_rule.jenkins_ssh : rule.cidr_ipv4]) == toset(["198.51.100.7/32"])
    error_message = "SSH to Jenkins is open to the admin CIDRs only."
  }

  assert {
    condition     = toset([for rule in aws_vpc_security_group_ingress_rule.jenkins_http : rule.from_port]) == toset([80, 443])
    error_message = "Only Caddy's HTTP/HTTPS ports are public on the Jenkins host."
  }
}

run "jenkins_iam_is_scoped_to_dev" {
  command = plan

  assert {
    condition = alltrue([
      for statement in jsondecode(data.aws_iam_policy_document.jenkins_dev_stack.json).Statement :
      alltrue([for resource in flatten([statement.Resource]) : strcontains(resource, "delivery-plus-dev")])
      if statement.Sid == "DevIam" || statement.Sid == "DevBuckets"
    ])
    error_message = "Jenkins may manage IAM and buckets of the dev stack only."
  }

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.jenkins_state.json).Statement : statement.Action
      if statement.Sid == "ReadPlatformState"
    ]) == "s3:GetObject"
    error_message = "Jenkins reads the platform state but never writes it."
  }
}

run "rejects_ssh_from_anywhere" {
  command = plan

  variables {
    admin_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.admin_cidrs]
}

run "rejects_a_private_key" {
  command = plan

  variables {
    ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----"
  }

  expect_failures = [var.ssh_public_key]
}
