# 0015 — costwatch UI ships inside the Go binary (embed.FS)

- **Status:** accepted
- **Date:** 2026-07-10

## Context

A SPA needs hosting: S3+CloudFront, a second container/sidecar, or embedding in
the API binary.

## Decision

`vite build` emits into `backend/web/dist`; `go:embed all:dist` serves it with
SPA index-fallback. One container, one Deployment, one image tag to promote.
The dist directory is gitignored (a fresh clone's binary serves an actionable
hint page); the Dockerfile builds UI → binary → distroless in three stages.

## Consequences

Deploy atomicity (UI and API can't skew), no CORS, no second origin to secure
for an internal tool, `make costwatch-demo` is the entire local stack. Costs:
UI-only changes rebuild the binary (fine at this scale), and assets ride in
container layers (~600 KB gzipped — acceptable; code-splitting noted for
later).

## Rejected

- **S3+CloudFront** — right for public high-traffic frontends; overkill plus
  a public path for a deliberately internal tool.
- **nginx sidecar/second deployment** — doubles the moving parts to solve a
  problem embed.FS doesn't have.
