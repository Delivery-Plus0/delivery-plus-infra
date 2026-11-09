variable "region" {
  description = "AWS region for the state bucket (use the same region as the stacks)."
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "delivery-plus"
}
