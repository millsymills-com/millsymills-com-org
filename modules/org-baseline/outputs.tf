output "org_name" {
  description = "Org slug under management."
  value       = var.org_name
}

output "settings" {
  description = "The github_organization_settings resource (used by tests; not for downstream wiring)."
  value       = github_organization_settings.this
}
