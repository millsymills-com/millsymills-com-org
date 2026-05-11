variable "name" {
  description = "Repository name."
  type        = string
}

variable "description" {
  description = "Short description shown on the repo page."
  type        = string
  default     = ""
}

variable "visibility" {
  description = "public, private, or internal."
  type        = string
  default     = "public"
  validation {
    condition     = contains(["public", "private", "internal"], var.visibility)
    error_message = "visibility must be public, private, or internal."
  }
}

variable "topics" {
  description = "Repo topics."
  type        = list(string)
  default     = []
}

variable "homepage_url" {
  description = "Homepage shown on the repo page."
  type        = string
  default     = ""
}

variable "has_issues" {
  type    = bool
  default = true
}

variable "is_template" {
  description = "If true, the repo can be used as a template when creating new repos."
  type        = bool
  default     = false
}

variable "archive_on_destroy" {
  description = "If true, the repo is archived rather than deleted on destroy."
  type        = bool
  default     = true
}
