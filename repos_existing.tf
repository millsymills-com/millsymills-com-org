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
      description  = "MCP server for UniFi Network, Protect, and Site Manager APIs. 82 tools, readonly by default with explicitly gated writes."
      homepage_url = ""
      has_issues   = true
      topics = [
        "fastmcp",
        "mcp",
        "model-context-protocol",
        "python",
        "ubiquiti",
        "unifi",
        "unifi-network",
        "unifi-protect",
      ]
      is_template = false
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
    shortcut-mcp = {
      name         = "shortcut-mcp"
      visibility   = "public"
      description  = "Python FastMCP server for the Shortcut REST API"
      homepage_url = ""
      has_issues   = true
      topics = [
        "fastmcp",
        "mcp",
        "mcp-server",
        "model-context-protocol",
        "project-management",
        "python",
        "rest-api",
        "shortcut",
      ]
      is_template = false
    }
    flipperzero-mcp = {
      name         = "flipperzero-mcp"
      visibility   = "public"
      description  = "Modular MCP server for the Flipper Zero (USB + WiFi protobuf RPC)"
      homepage_url = ""
      has_issues   = true
      topics = [
        "flipper-zero",
        "hardware",
        "mcp",
        "mcp-server",
        "model-context-protocol",
        "protobuf",
        "python",
        "rpc",
        "usb",
      ]
      is_template = false
    }
    # DO NOT add millsymills-com-org here.
  }
}

# shortcut-mcp and flipperzero-mcp were created after the Plan-1 baseline and
# drifted in unmanaged. Adopt them into state (alerts stay on; settings reconcile
# to the declarations above) rather than recreating. Same pattern as the
# management repo's import in repos_meta.tf.
import {
  to = module.existing["shortcut-mcp"].github_repository.this
  id = "shortcut-mcp"
}

import {
  to = module.existing["flipperzero-mcp"].github_repository.this
  id = "flipperzero-mcp"
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
