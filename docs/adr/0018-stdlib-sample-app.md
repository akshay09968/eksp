# 0018 — sample-api stays stdlib-only (plus the Prometheus client)

- **Status:** accepted
- **Date:** 2026-07-10

## Context

The scale-demo service could use a router/framework (chi, gin, echo) and
assorted middleware. Its actual jobs: serve HTTP fast, expose RED metrics,
fan out to the worker, and demonstrate a correct drain.

## Decision

`net/http` with 1.22+ method routing, `log/slog`, and exactly one dependency:
`prometheus/client_golang`. One binary serves both roles (`ROLE=api|worker`) —
the mesh gets real east-west traffic without a second codebase.

## Consequences

The whole service is one readable file + tests; the interesting parts (drain
choreography, bounded-cardinality instrumentation, tuned Transport) aren't
buried under framework idiom. Anyone who reviews Go can review all of it.
Trade: no framework conveniences — irrelevant at four routes.

## Rejected

- **chi/gin/echo** — fine tools solving problems this service doesn't have.
- **Two services for api/worker** — double the manifests and images for zero
  additional demonstration value; an env var does it.
