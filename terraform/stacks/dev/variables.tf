variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "project" {
  type    = string
  default = "delivery-plus"
}

variable "environment" {
  description = "Environment name; also the bucket and IAM path suffix (Jenkins' role is scoped to \"dev\")."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment is lowercase letters, digits and dashes."
  }
}

variable "state_bucket" {
  description = "The Terraform state bucket; this stack reads the platform stack's outputs from it."
  type        = string
}

variable "app_instance_type" {
  description = "12 services, Postgres, Redis, Kafka and Zookeeper need about 6 GiB: t3.large (8 GiB)."
  type        = string
  default     = "t3.large"
}

variable "app_root_volume_size" {
  description = "Root disk in GiB: OS and Docker images."
  type        = number
  default     = 40
}

variable "app_data_volume_size" {
  description = "Data disk in GiB: Postgres, Kafka, Redis, Caddy certificates, generated secrets."
  type        = number
  default     = 50
}

variable "base_domain" {
  description = "Domain the apps are served under (api., app., driver., restaurant.). Empty: <ip>.sslip.io."
  type        = string
  default     = ""
}

variable "extra_app_origins" {
  description = "More browser origins allowed by CORS (gateway and media bucket), e.g. Expo on a developer machine."
  type        = list(string)
  default     = ["http://localhost:8081", "http://localhost:8082", "http://localhost:8083"]
}

variable "enable_ses" {
  description = "Let auth-service send email through Amazon SES (EMAIL_PROVIDER=ses). Off: email codes are disabled."
  type        = bool
  default     = false
}

variable "ses_from_address" {
  description = "Verified SES sender when enable_ses is true, e.g. no-reply@example.com."
  type        = string
  default     = ""

  validation {
    condition     = var.ses_from_address == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.ses_from_address))
    error_message = "ses_from_address must be an email address."
  }
}
