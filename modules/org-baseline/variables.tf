variable "org_name" {
  description = "GitHub org slug to manage."
  type        = string
}

variable "billing_email" {
  description = "Org billing contact email shown in the org settings."
  type        = string
}

variable "display_name" {
  description = "Org display name shown on the org page."
  type        = string
}

variable "description" {
  description = "Public one-line org description shown on the org page."
  type        = string
  default     = ""
}

variable "blog" {
  description = "Public website URL shown on the org page."
  type        = string
  default     = ""
}

variable "location" {
  description = "Public location shown on the org page."
  type        = string
  default     = ""
}
