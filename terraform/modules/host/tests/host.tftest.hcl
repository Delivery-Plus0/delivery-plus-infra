# A mocked AWS provider: no account, no network, and `apply` works, so values AWS would compute
# (the Elastic IP, the volume id) are known and checkable. Same in Terraform and OpenTofu.

mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { id = "ami-0123456789abcdef0" }
  }

  mock_data "aws_subnet" {
    defaults = { availability_zone = "eu-central-1a" }
  }

  mock_resource "aws_eip" {
    defaults = { public_ip = "203.0.113.10", id = "eipalloc-0123456789abcdef0" }
  }

  mock_resource "aws_ebs_volume" {
    defaults = { id = "vol-0123456789abcdef0" }
  }

  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/delivery-plus-dev/delivery-plus-dev-app-host" }
  }
}

variables {
  name               = "delivery-plus-dev-app"
  role               = "app"
  instance_type      = "t3.large"
  subnet_id          = "subnet-0123456789abcdef0"
  security_group_ids = ["sg-0123456789abcdef0"]
  key_name           = "delivery-plus-deploy"
  iam_path           = "delivery-plus-dev"
}

run "hardened_instance" {
  command = apply

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_put_response_hop_limit == 2
    error_message = "Containers reach the instance role only with a hop limit of 2."
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted && aws_ebs_volume.data.encrypted
    error_message = "Root and data volumes must be encrypted."
  }

  assert {
    condition     = aws_iam_role.this.path == "/delivery-plus-dev/"
    error_message = "The role lives under the environment's IAM path (Jenkins is scoped to it)."
  }
}

run "sslip_domain_from_static_ip" {
  command = apply

  assert {
    condition     = output.base_domain == "203-0-113-10.sslip.io"
    error_message = "Without base_domain, the host is served under <elastic-ip>.sslip.io."
  }

  assert {
    condition     = aws_instance.this.tags["BaseDomain"] == "203-0-113-10.sslip.io" && aws_instance.this.tags["Role"] == "app"
    error_message = "Ansible reads BaseDomain and Role from the instance tags."
  }

  assert {
    condition     = aws_instance.this.tags["DataVolumeId"] == "vol-0123456789abcdef0"
    error_message = "Ansible finds the data volume through the DataVolumeId tag."
  }
}

run "own_domain" {
  command = apply

  variables {
    base_domain = "dev.example.com"
  }

  assert {
    condition     = output.base_domain == "dev.example.com"
    error_message = "A configured base_domain wins over sslip.io."
  }
}

run "rejects_unknown_role" {
  command = plan

  variables {
    role = "database"
  }

  expect_failures = [var.role]
}
