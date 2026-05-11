variable "ruleset_name" {
  type    = string
  default = "tag-protection"
}

variable "tag_pattern" {
  description = "Glob pattern for tags to protect. Default v* covers semver release tags."
  type        = string
  default     = "v*"
}

variable "enforcement" {
  description = "active = block, evaluate = log-only (dry-run), disabled = off."
  type        = string
  default     = "active"
  validation {
    condition     = contains(["active", "evaluate", "disabled"], var.enforcement)
    error_message = "enforcement must be active, evaluate, or disabled."
  }
}
