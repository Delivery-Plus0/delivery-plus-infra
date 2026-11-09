# Plan-only tests with the real AWS provider and fake credentials: no AWS account or network needed.
# The platform stack's outputs are stubbed.

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
  target = data.terraform_remote_state.platform
  values = {
    outputs = {
      region                    = "eu-central-1"
      vpc_id                    = "vpc-0123456789abcdef0"
      vpc_cidr                  = "10.40.0.0/16"
      public_subnet_id          = "subnet-0123456789abcdef0"
      key_name                  = "delivery-plus-deploy"
      ecr_registry              = "123456789012.dkr.ecr.eu-central-1.amazonaws.com"
      ecr_repository_arns       = ["arn:aws:ecr:eu-central-1:123456789012:repository/delivery-plus/api-gateway"]
      jenkins_security_group_id = "sg-0123456789abcdef0"
      admin_cidrs               = ["198.51.100.7/32"]
    }
  }
}

override_data {
  target = module.app.data.aws_ami.ubuntu
  values = { id = "ami-0123456789abcdef0" }
}

override_data {
  target = module.app.data.aws_subnet.this
  values = { availability_zone = "eu-central-1a" }
}

variables {
  state_bucket = "delivery-plus-tfstate-123456789012"
  base_domain  = "dev.example.com"
}

run "only_the_web_is_public" {
  command = plan

  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_ingress_rule.app_web : contains([80, 443], rule.from_port)])
    error_message = "Only Caddy (80/443) is reachable from the internet; Postgres, Redis, Kafka and the services are not."
  }

  assert {
    condition     = toset([for rule in aws_vpc_security_group_ingress_rule.app_ssh_admins : rule.cidr_ipv4]) == toset(["198.51.100.7/32"])
    error_message = "SSH comes from the admin CIDRs."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.app_ssh_jenkins.referenced_security_group_id == "sg-0123456789abcdef0"
    error_message = "Jenkins reaches the host over the VPC by security group."
  }
}

run "urls_follow_the_domain" {
  command = plan

  assert {
    condition     = output.api_url == "https://api.dev.example.com"
    error_message = "The API is served at api.<domain>."
  }

  assert {
    condition     = output.app_urls.driver == "https://driver.dev.example.com"
    error_message = "The driver app is served at driver.<domain>."
  }
}

run "ses_needs_a_sender" {
  command = plan

  variables {
    enable_ses = true
  }

  expect_failures = [check.ses_sender]
}

run "t3_large_by_default" {
  command = plan

  assert {
    condition     = var.app_instance_type == "t3.large"
    error_message = "The agreed dev size is t3.large (8 GiB)."
  }
}
