# Contributing

Solo-maintained portfolio project, but PRs are welcome and the bar is the same
for everyone (including AI agents — see [AGENTS.md](AGENTS.md)):

1. `make check` green locally — it's exactly what CI runs, no cloud needed.
2. Conventional commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`).
3. New decision → ADR ([docs/adr/template.md](docs/adr/template.md)).
   New alert → RUNBOOK anchor. New variable → description + validation.
4. No invented benchmark numbers; scale claims follow
   [SCALING.md](docs/SCALING.md)'s design-target/recorded-result discipline.
5. `pre-commit install` once — fmt, tflint, and gitleaks run on commit.
