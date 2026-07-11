---
name: new-adr
description: Record an architecture decision as an ADR. Use when a PR introduces or changes a non-obvious decision (tool choice, boundary, trade-off), when the user says "write an ADR", or when review comments reveal a decision that isn't written down anywhere.
---

# Recording an ADR

1. Next number: `ls docs/adr/ | grep -Eo '^[0-9]{4}' | sort | tail -1` + 1.
2. Copy `docs/adr/template.md` → `docs/adr/NNNN-<kebab-slug>.md`.
3. Fill every section. The **Rejected** section is the point — each
   alternative gets one honest sentence on why not. No alternatives considered
   = it wasn't a decision, don't write an ADR.
4. Add the row to the table in `docs/adr/README.md` (keep numeric order).
5. Link it from the code that embodies it (a one-line comment like
   `# ADR-00NN`) and from any doc that states the decision.
6. If it supersedes an older ADR: mark the old one
   `Status: superseded by NNNN` — never delete or rewrite old ADRs.
7. Same commit as the change it explains, message `docs(adr): NNNN <title>`.

Style: imperative title (the decision itself), two-paragraph context max,
declarative decision, consequences include what gets *harder*. Read 0011 or
0017 for tone.
