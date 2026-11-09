output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  description = "The Elastic IP: static for the life of the stack, across stops and replacements."
  value       = aws_eip.this.public_ip
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "base_domain" {
  value = local.base_domain
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "data_volume_id" {
  value = aws_ebs_volume.data.id
}
