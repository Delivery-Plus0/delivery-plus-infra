variable "name" {
  description = "Bucket name prefix, e.g. delivery-plus-dev. The account ID is appended for uniqueness."
  type        = string
}

variable "account_id" {
  type = string
}

variable "app_origins" {
  description = "Browser origins of the three apps (CORS for presigned uploads to the media bucket)."
  type        = list(string)

  validation {
    condition     = alltrue([for origin in var.app_origins : can(regex("^https?://[^/]+$", origin))])
    error_message = "Each origin is scheme://host[:port] with no path."
  }
}

variable "document_upload_origins" {
  description = "Origins allowed to POST driver documents (the driver app only)."
  type        = list(string)
}

variable "media_public_prefixes" {
  description = "Media prefixes readable by anyone once an upload is confirmed."
  type        = list(string)
  default     = ["users/", "restaurants/"]

  validation {
    condition     = alltrue([for prefix in var.media_public_prefixes : endswith(prefix, "/") && !startswith(prefix, "pending")])
    error_message = "Prefixes end with / and never include pending/."
  }
}

variable "force_destroy" {
  description = "Allow destroying buckets that still hold objects (dev only)."
  type        = bool
  default     = true
}
