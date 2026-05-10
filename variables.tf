variable "org_name" {
  description = "GitHub org slug."
  type        = string
  default     = "millsymills-com"
}

variable "github_app_id" {
  description = "App ID for the GitHub App used in this run (writer or reader)."
  type        = string
}

variable "github_app_installation_id" {
  description = "Installation ID for the GitHub App."
  type        = string
}

variable "github_app_pem_file" {
  description = "Filesystem path to the GitHub App PEM. CI writes the PEM to RUNNER_TEMP at mode 0600 and points this var at that path; locally, point it at a path you control. Never the PEM contents."
  type        = string
}

variable "aws_region" {
  description = "AWS region for state and KMS."
  type        = string
  default     = "us-west-1"
}
