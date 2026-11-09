# The dev stack reads these through terraform_remote_state.

output "region" {
  value = var.region
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "public_subnet_id" {
  value = module.network.public_subnet_id
}

output "key_name" {
  value = aws_key_pair.deploy.key_name
}

output "ecr_registry" {
  value = module.ecr.registry
}

output "ecr_repository_arns" {
  value = module.ecr.repository_arns
}

output "jenkins_security_group_id" {
  value = aws_security_group.jenkins.id
}

output "jenkins_public_ip" {
  value = module.jenkins.public_ip
}

output "jenkins_private_ip" {
  value = module.jenkins.private_ip
}

output "jenkins_url" {
  value = "https://jenkins.${module.jenkins.base_domain}"
}

output "admin_cidrs" {
  value = var.admin_cidrs
}

output "ssh_jenkins" {
  value = "ssh ubuntu@${module.jenkins.public_ip}"
}
