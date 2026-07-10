# Load scenarios

Executable SLOs: thresholds fail the run, so "did we meet p99 < 150ms at 0.1%
errors" is a CI-style pass/fail, not a judgment call. Full methodology, capacity
math, and generator sizing: [docs/SCALING.md](../../docs/SCALING.md).

| Scenario | Shape | Question it answers |
|---|---|---|
| `smoke.js` | 50 RPS × 1m | Is the path healthy enough to bother testing? |
| `ramp.js` | steps → `TARGET_RPS`, hold 10m | Where does the system break first? |
| `spike.js` | 3× step in 10s | Karpenter + HPA reaction: time-to-recovery of p99 |
| `soak.js` | 60% × 30m | What leaks or churns over time? |

```bash
# local / dev sanity
BASE_URL=http://<alb-dns> make k6-smoke

# the headline run (needs a serious generator — see SCALING.md#method)
BASE_URL=http://<lb-dns> TARGET_RPS=17000 make k6-ramp

# through the mesh path (api → worker fan-out)
BASE_URL=http://<lb-dns> CHAIN=1 k6 run load/k6/ramp.js
```

Honesty rule (also in CLAUDE.md): numbers in docs are **design targets** until a
run is recorded. When you run one, append the k6 summary + cluster state
(`kubectl top nodes`, HPA status) to `docs/SCALING.md#results`.
