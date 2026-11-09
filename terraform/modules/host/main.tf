# One EC2 host: Ubuntu 24.04, an Elastic IP (the static address clients and DNS use), a separate
# encrypted data volume that outlives the instance, and an instance role.
#
# The data volume holds everything stateful (Postgres, Kafka, Redis, Jenkins home, generated secrets),
# so replacing the instance (a new AMI, a new size) keeps the data. Ansible finds it by the
# DataVolumeId tag, formats it once and mounts it at `data_mount_point`.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_subnet" "this" {
  id = var.subnet_id
}

resource "aws_eip" "this" {
  domain = "vpc"

  # The address is what clients, CORS origins and TLS certificates are bound to: it stays the same
  # across instance stops and replacements, and changes only if the stack is destroyed.
  tags = { Name = var.name }
}

locals {
  # A real DNS name for the static IP without owning a domain: sslip.io resolves
  # <anything>.<a-b-c-d>.sslip.io to a.b.c.d, so Caddy can get Let's Encrypt certificates for it.
  base_domain = coalesce(var.base_domain, "${replace(aws_eip.this.public_ip, ".", "-")}.sslip.io")
}

resource "aws_iam_role" "this" {
  name = "${var.name}-host"
  path = "/${var.iam_path}/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "this" {
  for_each = var.role_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-host"
  path = "/${var.iam_path}/"
  role = aws_iam_role.this.name
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.this.name
  monitoring             = false
  ebs_optimized          = true

  # IMDSv2 only. Hop limit 2 lets containers (one extra network hop) reach the instance role,
  # which is how the services get S3 credentials without any keys in files.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  tags = merge(var.tags, {
    Name         = var.name
    Role         = var.role
    BaseDomain   = local.base_domain
    PublicIp     = aws_eip.this.public_ip
    DataVolumeId = aws_ebs_volume.data.id
    DataMount    = var.data_mount_point
  })

  lifecycle {
    # A newer Ubuntu AMI must not replace a running dev host by surprise; replace it on purpose
    # with `terraform apply -replace=...` (the data volume survives).
    ignore_changes = [ami]
  }
}

resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.this.availability_zone
  type              = "gp3"
  size              = var.data_volume_size
  encrypted         = true

  tags = merge(var.tags, { Name = "${var.name}-data", Role = var.role })
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.this.id

  # On a replacement, stop the instance's use of the volume cleanly before detaching.
  stop_instance_before_detaching = true
}

resource "aws_eip_association" "this" {
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this.id
}
