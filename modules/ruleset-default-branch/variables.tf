variable "ruleset_name" {
  type    = string
  default = "default-branch-protection"
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

variable "required_status_checks" {
  description = "Status check contexts that must pass before merge."
  type        = list(string)
  default     = []
}

variable "required_approving_review_count" {
  type    = number
  default = 0
}
