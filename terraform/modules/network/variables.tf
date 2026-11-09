variable "name" {
  description = "Name prefix, e.g. delivery-plus."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. The public subnet is its /24 number 1."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && tonumber(split("/", var.cidr_block)[1]) <= 16
    error_message = "cidr_block must be a valid IPv4 CIDR of /16 or larger."
  }
}

variable "availability_zone" {
  description = "AZ for the subnet; the region's first available AZ when null."
  type        = string
  default     = null
}
