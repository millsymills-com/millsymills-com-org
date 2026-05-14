locals {
  # Explicitly excludes the management repo "millsymills-com-org" — it is
  # imported in Task 16a directly into `module.management_repo`. Letting it
  # land here would cause a state-conflict error or, worse, a double-managed
  # repo.
  existing_repos = {
    unraid-mcp = {
      name         = "unraid-mcp"
      visibility   = "public"
      description  = "Production-grade Python MCP server for the Unraid GraphQL API"
      homepage_url = ""
      has_issues   = true
      topics = [
        "claude",
        "fastmcp",
        "graphql",
        "home-automation",
        "homelab",
        "mcp",
        "mcp-server",
        "model-context-protocol",
        "nas",
        "python",
        "unraid",
      ]
      is_template = true
    }
    protonmail-mcp = {
      name         = "protonmail-mcp"
      visibility   = "public"
      description  = "MCP server for Proton Mail — manage addresses, custom domains, mail settings, and encryption keys from Claude Code or any MCP host."
      homepage_url = ""
      has_issues   = true
      topics = [
        "claude-code",
        "golang",
        "mcp",
        "mcp-server",
        "model-context-protocol",
        "proton-mail",
        "protonmail",
      ]
      is_template = false
    }
    unifi-mcp = {
      name         = "unifi-mcp"
      visibility   = "public"
      description  = ""
      homepage_url = ""
      has_issues   = true
      topics       = []
      is_template  = false
    }
    gandi-mcp = {
      name         = "gandi-mcp"
      visibility   = "public"
      description  = "Python MCP server for the Gandi v5 API: domains, LiveDNS, email, billing, organizations, and certificates. Three-tier safety model gates writes and purchases."
      homepage_url = ""
      has_issues   = true
      topics = [
        "claude",
        "claude-code",
        "dns",
        "domain-management",
        "fastmcp",
        "gandi",
        "livedns",
        "mcp",
        "mcp-server",
        "model-context-protocol",
        "python",
        "registrar",
        "tls-certificates",
      ]
      is_template = false
    }
    # DO NOT add millsymills-com-org here.
  }
}

module "existing" {
  source   = "./modules/repo-baseline"
  for_each = local.existing_repos

  name         = each.value.name
  visibility   = each.value.visibility
  description  = each.value.description
  homepage_url = each.value.homepage_url
  has_issues   = each.value.has_issues
  topics       = each.value.topics
  is_template  = each.value.is_template
}

# Import existing vulnerability-alert state for repos that previously had
# alerts enabled via the now-removed inline `vulnerability_alerts` arg on
# `github_repository`. Without this, the new sibling resource would plan
# a create on an already-enabled flag (no-op API-wise, but state-noisy).
import {
  for_each = local.existing_repos
  to       = module.existing[each.key].github_repository_vulnerability_alerts.this
  id       = each.value.name
}
