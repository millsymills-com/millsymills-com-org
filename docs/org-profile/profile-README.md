# millsymills.com

Security engineering, MCP tooling, and infrastructure managed as code.

I'm **Andrew Mills** — I build [Model Context Protocol](https://modelcontextprotocol.io)
servers that give AI agents safe, scoped access to real systems, and I run the
infrastructure behind them the same way I'd secure anything else: declared in
code, reviewed in pull requests, and enforced by CI.

Based in the Pacific Northwest · Remote.

## MCP servers

Each is a standalone server with a read-only-by-default posture and explicit
gating on any write.

| Server | Stack | What it does |
|--------|-------|--------------|
| [unraid-mcp](https://github.com/millsymills-com/unraid-mcp) | Python · FastMCP | Unraid GraphQL API — array, Docker, VMs, shares. |
| [unifi-mcp](https://github.com/millsymills-com/unifi-mcp) | Python · FastMCP | UniFi Network, Protect, and Site Manager — 82 tools, writes explicitly gated. |
| [gandi-mcp](https://github.com/millsymills-com/gandi-mcp) | Python · FastMCP | Gandi v5 — domains, LiveDNS, email, certificates. Three-tier safety model on writes and purchases. |
| [protonmail-mcp](https://github.com/millsymills-com/protonmail-mcp) | Go | Proton Mail — addresses, custom domains, mail settings, encryption keys. |
| [flipperzero-mcp](https://github.com/millsymills-com/flipperzero-mcp) | Python | Flipper Zero over USB and Wi-Fi protobuf RPC. |
| [shortcut-mcp](https://github.com/millsymills-com/shortcut-mcp) | Python · FastMCP | Shortcut REST API — stories, epics, workflows. |

## Infrastructure

[**millsymills-com-org**](https://github.com/millsymills-com/millsymills-com-org)
manages this entire organization as code with OpenTofu: org settings, org-wide
rulesets, and per-repo configuration — including the repo that manages it.

## How this org is run

- **OIDC-only CI** — no static cloud credentials anywhere; workflows assume
  short-lived roles scoped to a single environment.
- **PR-gated changes** — every org and repo setting is declared in OpenTofu;
  `pull request → plan → merge → apply`, with nightly drift detection.
- **Pinned supply chain** — GitHub Actions pinned to commit SHAs, egress-blocked
  runners, and a synthesizer gate that closes the "skipped == passing" loophole.
- **Signed releases** — SSH-signed tags with an allowed-signers allowlist and
  tag-immutability rulesets.
- **Scanned continuously** — gitleaks, zizmor, CodeQL, and OpenSSF Scorecard on
  every change.

## Contact

[millsymills.com](https://millsymills.com) · mills@millsymills.com
