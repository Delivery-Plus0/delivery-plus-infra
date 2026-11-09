variable "region" {
  description = "AWS region for every resource."
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "delivery-plus"
}

variable "state_bucket" {
  description = "The Terraform state bucket (from terraform/bootstrap). Jenkins gets access to the dev stack's state in it."
  type        = string
}

variable "admin_cidrs" {
  description = "Addresses allowed to SSH into the hosts, e.g. [\"41.33.10.20/32\"]. Never 0.0.0.0/0."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for cidr in var.admin_cidrs : can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0"])
    error_message = "admin_cidrs needs at least one valid CIDR, and SSH is never open to 0.0.0.0/0."
  }
}

variable "ssh_public_key" {
  description = "Public key of the deploy key pair (the private half goes into Jenkins as the app-ssh credential)."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key (ssh-ed25519 recommended)."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "jenkins_instance_type" {
  description = "Jenkins builds 12 service images and three web apps; 4 GiB is the practical minimum."
  type        = string
  default     = "t3.medium"
}

variable "jenkins_data_volume_size" {
  description = "Jenkins home (jobs, workspaces) in GiB."
  type        = number
  default     = 40
}

variable "jenkins_root_volume_size" {
  description = "Root disk in GiB: Docker images and BuildKit cache for the image builds."
  type        = number
  default     = 50
}

variable "jenkins_base_domain" {
  description = "Domain Jenkins is served under (jenkins.<domain>). Empty: <ip>.sslip.io."
  type        = string
  default     = ""
}

variable "services" {
  description = "Backend services that get an ECR repository (the 11 services and the gateway)."
  type        = list(string)
  default = [
    "api-gateway",
    "auth-service",
    "user-service",
    "restaurant-service",
    "menu-service",
    "cart-service",
    "order-service",
    "payment-service",
    "delivery-service",
    "driver-service",
    "tracking-service",
    "notification-service",
  ]
}
