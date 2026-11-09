variable "name" {
  description = "Host name and resource name prefix, e.g. delivery-plus-dev-app."
  type        = string
}

variable "role" {
  description = "Ansible group of the host: app or jenkins (the Role tag)."
  type        = string

  validation {
    condition     = contains(["app", "jenkins"], var.role)
    error_message = "role must be app or jenkins."
  }
}

variable "instance_type" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "key_name" {
  description = "EC2 key pair for SSH (Ansible)."
  type        = string
}

variable "root_volume_size" {
  description = "Root disk in GiB: OS, Docker images and build cache."
  type        = number
  default     = 30
}

variable "data_volume_size" {
  description = "Data disk in GiB: databases, Kafka logs, Jenkins home, secrets."
  type        = number
  default     = 30
}

variable "data_mount_point" {
  description = "Where Ansible mounts the data volume."
  type        = string
  default     = "/srv/data"
}

variable "base_domain" {
  description = "DNS name the host serves under. Empty: <ip-with-dashes>.sslip.io from the Elastic IP."
  type        = string
  default     = ""
}

variable "iam_path" {
  description = "IAM path for the role and instance profile (scopes the CI role's IAM permissions)."
  type        = string
  default     = "delivery-plus"
}

variable "role_policies" {
  description = "Inline policies for the instance role: name => JSON document."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Extra tags on the instance and data volume (Ansible reads some of them)."
  type        = map(string)
  default     = {}
}
