# 0019 — GitHub SSO via each tool's native OIDC, not a shared broker

- **Status:** accepted
- **Date:** 2026-07-17

## Context

Three operator UIs (ArgoCD, Grafana, costwatch) had no authentication —
port-forward-only access with a local admin password. SOC 2 CC6 treats UI
authn as table stakes even for internal tools; it was the top item on the
SECURITY.md hardening list. The identity source was never in question: GitHub
is already this project's anchor (CI runs on GitHub OIDC, the repo lives there,
the operator account already carries `admin:org`), so GitHub org **teams → RBAC
roles** maps for free with no new vendor or tenant.

The open question was topology: run a standalone identity broker (Dex/Keycloak)
that federates to GitHub and serves one OIDC issuer to all three apps, or use
each tool's first-class GitHub integration directly.

## Decision

Each app uses its own native GitHub path, no standalone broker:

- **ArgoCD** — its bundled Dex with a `github` connector (Dex is already in the
  chart; this just enables and configures it). RBAC policy maps a GitHub team to
  `role:admin`, everyone else read-only.
- **Grafana** — native `auth.github`, org-restricted, team → Viewer/Editor/Admin.
- **costwatch** — a plain Go app with no auth, so oauth2-proxy (`provider=github`,
  org+team restricted) fronts it on an internal ALB. This is the one place a
  proxy is correct; the others would have their CLIs/gRPC broken by one.

All three read their OAuth **client secret** from a Kubernetes Secret the
operator creates out-of-band (`docs/RUNBOOK.md#github-sso`); nothing secret is
committed or lands in Terraform state. The ArgoCD side is gated on a
`github_sso_org` variable so the platform still applies cleanly with SSO
unconfigured.

## Consequences

Fewer moving parts — no fourth component to deploy and expose, and each piece is
the tool's blessed, documented path (a proxy in front of ArgoCD breaks its
CLI/gRPC; native OIDC doesn't). One GitHub OAuth app per UI (three trivial, free
registrations). Costs: three team→role mappings to keep in sync instead of one,
and no single issuer to point a future corporate IdP at.

That last cost is the documented evolution: when a real org IdP enters (Okta,
Entra), stand up Dex/Keycloak as a broker federating to it, and repoint each
app's `issuer` at the broker — the connector changes in one place, the app RBAC
configs don't. The broker is deferred, not rejected.

## Rejected

- **Standalone shared Dex now** — one issuer + one team map is architecturally
  tidy, but for three apps it adds a component that itself needs HTTPS exposure,
  buys little over native integrations, and is premature without a second
  upstream IdP to broker. Kept as the evolution above.
- **oauth2-proxy in front of all three** (the issue's original framing) — breaks
  the ArgoCD CLI/gRPC and throws away Grafana's native team→role mapping. Match
  the mechanism to the app.
- **Auth0 / Okta / Entra** — the right answer in an org with an existing tenant;
  for a solo GitHub-anchored project it adds a vendor without adding capability.
  Named here as the interview framing: "GitHub now; broker to the corporate IdP
  later, nothing downstream changes."
