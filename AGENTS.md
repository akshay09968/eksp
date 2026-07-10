# Agent instructions

Canonical, tool-agnostic instructions for this repository live in **[CLAUDE.md](CLAUDE.md)**
(map, boundary rule, commands, conventions, definition of done, guardrails).
All coding agents should follow that file; nothing here overrides it.

Quick orientation for any agent:

- Validate offline with `make check` — it needs no AWS credentials.
- Do not apply/destroy infrastructure or mutate clusters; those are human actions.
- Decisions are recorded in `docs/adr/` — read the relevant ADR before changing
  architecture-shaped code, and add one when you introduce a new decision.
