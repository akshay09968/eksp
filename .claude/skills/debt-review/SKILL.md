---
name: debt-review
description: Periodic technical-debt sweep of the whole repo. Use when the user asks for a debt/health review, runs /debt-review (possibly on a schedule), or asks "what will bite us later". Produces verified findings, files them as issues, and logs the review.
---

# Technical-debt review

A recurring, evidence-based sweep. The output is *verified findings*, not
vibes: every claim gets checked against the repo before it's reported —
this repo deliberately contains things that look like mistakes (no CPU
limits, us-east-1 CE client, dev-only ALB Ingress, per-env duplication).

## Ground rules

- **Read first, flag second**: before calling anything debt, check
  `docs/adr/` (all of them are one-line indexed in `docs/adr/README.md`),
  `docs/AUDIT.md` (known + accepted items), and `docs/COMPLIANCE.md`.
  An accepted, documented trade-off is not a finding. A trade-off whose
  *documentation has drifted from the code* is.
- **Dedupe**: `gh issue list --state all --limit 50` — never re-file a
  known item; comment on the existing issue if there's new evidence.
- **Verify negatives with tooling, not memory**: a "missing X" finding must
  show the command that failed to find X. Beware shell traps (zsh aborts
  whole commands on failed globs — a past review mis-reported a present
  file as missing this way).
- **No invented numbers**, no `terraform apply`, no mutating `kubectl`
  (root CLAUDE.md guardrails apply in full).

## The sweep (run all, collect evidence)

1. **Baseline**: `make check` — if it isn't green, that's finding #1 and
   the review pauses until it's explained.
2. **Dependency rot**: open Renovate PRs sitting unmerged
   (`gh pr list --author 'app:renovate'`); if zero PRs *ever*, check the
   app is still enabled. Spot-check the oldest pins:
   chart `targetRevision`s vs upstream, `ami_alias` date age,
   `kubernetes_version` vs endoflife.date, Go/Node toolchains.
3. **CI health**: `actionlint`; any workflow that hasn't run green
   recently (`gh run list --limit 20`); any action not SHA-pinned
   (`grep -rn "uses:" .github/ | grep -v '@[0-9a-f]\{40\}' | grep -v 'uses: \./'`).
4. **Validation blind spots**: kubeconform `Skipped:` counts in the
   `make check` output (should be 0); new resource kinds without schemas;
   scripts in `scripts/` not wired into `make check`.
5. **Skew and parity**: `STRICT_CHART_SKEW=1 ./scripts/check-chart-skew.sh`
   (skew is fine mid-promotion — flag only if the same skew appeared in the
   previous review's log); `./scripts/check-env-parity.sh`.
6. **Docs honesty**: every ✅ in COMPLIANCE.md/SECURITY.md still true in
   code? Every ❌/⚠️ still actually missing? RUNBOOK anchors referenced by
   alerts/comments still exist?
7. **Lifecycle clocks**: EKS version EOL date, AMI pin age (>90d without a
   bump = Renovate is broken or ignored), cert/TLS issue (#1) status.
8. **Code smells**: `grep -rn "TODO\|FIXME\|XXX" --include="*.go" --include="*.tf" --include="*.sh" --include="*.yaml" apps/ terraform/ gitops/ scripts/`
   — anything older than the last review; coverage floors vs actual
   (`go test -cover`); dead flags/variables nothing references.
9. **DR/backup posture**: state replication still configured; anything
   newly *stateful* in `gitops/` that invalidates the "Velero not needed"
   determination in COMPLIANCE.md.

## Output contract

1. Prioritized findings, each with: evidence (command + output), why it
   bites later, cheapest prevention now. Explicitly list "checked, still
   fine" categories too — a clean bill needs to be auditable.
2. File each actionable finding as a `good-for-agents` issue with
   acceptance criteria (after the dedupe pass). Fix in-session only what
   is trivial *and* the user asked for fixes; otherwise stop at filing.
3. Append a dated entry to the remediation log in `docs/AUDIT.md`:
   date, findings count, issues filed, categories checked clean. This log
   is what makes the *next* review's "new since last time" cheap.
4. Commit only the AUDIT.md log entry (message
   `docs(audit): debt review YYYY-MM-DD`) unless fixes were requested.
