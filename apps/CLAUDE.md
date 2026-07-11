# apps/ conventions

Loaded when working in this tree. Two services, one bar: TDD, small
dependency surface, drain correctness.

## Go (both services)

- stdlib-first (ADR-0018): `net/http` 1.22+ method routing, `log/slog`,
  Prometheus client. New dependency = justify in the PR.
- Tests first. CI enforces coverage floors: sample-api ≥65%, costwatch ≥75%
  (`app.yml`) — raise the floor when you raise coverage, never lower it.
- Metric labels are bounded: route labels are static strings, never raw URL
  paths (cardinality is a production outage, not a style point).
- The drain contract (do not break): SIGTERM → `/readyz` fails →
  keep serving `SHUTDOWN_DELAY` (15s) → `server.Shutdown`. Distroless has no
  shell — there is no preStop; the app owns its lifecycle.
  `terminationGracePeriodSeconds` (45s) > delay + ALB deregistration (30s).
- Determinism lesson (learned the hard way, see AUDIT remediation log):
  anything summing floats over a Go map must iterate in sorted-key order —
  and any "deterministic" promise gets a repeated-run test.

## costwatch specifics

- `internal/costs.CostExplorerAPI` is the consumer-owned interface — all
  aggregation logic is tested against mocks + the demo client; never against
  real AWS in unit tests.
- Cost Explorer bills ~$0.01/request: anything that adds query shapes must
  respect the cache (TTL+singleflight, 256-entry cap) and the
  `ALLOWED_TAG_KEYS` allowlist (AUDIT P0-1). New query dimension = new test
  proving it can't bypass either.
- CE client region is us-east-1 on purpose (the API only exists there).
- Errors are product surfaces: unavailable features return actionable hints
  (see the hourly-opt-in 409), not raw AWS errors.

## Frontend (costwatch/frontend)

- Colors come from `theme.ts` (validated dataviz palette): categorical slots
  in fixed order, color follows the entity (slot map), status colors reserved
  for deltas, "Other" is always the neutral gray. `theme.test.ts` enforces
  slot stability — extend it if you touch assignment.
- `npm run test` (vitest) + `npm run build` (tsc + vite) both gate CI.
- Build emits into `../backend/web/dist` (embed.FS, ADR-0015) — don't move it.
