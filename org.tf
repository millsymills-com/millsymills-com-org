module "org_baseline" {
  source = "./modules/org-baseline"

  org_name      = var.org_name
  billing_email = "mills@millsymills.com"
  display_name  = "millsymills.com"
}
