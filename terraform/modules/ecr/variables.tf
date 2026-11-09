variable "prefix" {
  description = "Repository namespace, e.g. delivery-plus."
  type        = string
}

variable "services" {
  description = "Backend services that get an image repository."
  type        = list(string)

  validation {
    condition     = length(var.services) == length(distinct(var.services))
    error_message = "services must not repeat."
  }
}

variable "keep_images" {
  description = "Images kept per repository (older ones expire)."
  type        = number
  default     = 15
}

variable "force_delete" {
  description = "Allow destroying repositories that still hold images (dev only)."
  type        = bool
  default     = true
}
