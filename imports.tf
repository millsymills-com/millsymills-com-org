# Temporary file. Imports existing org-level resources into Tofu state.
# Removed after the first successful apply (see Task 12 step 6).
import {
  to = module.org_baseline.github_organization_settings.this
  id = "millsymills-com"
}
