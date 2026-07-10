// Shared configuration for all scenarios. Every knob is an env var so the same
// scripts serve dev smoke tests and the prod 17k-RPS ramp:
//
//   BASE_URL    target (default http://localhost:8080)
//   TARGET_RPS  steady-state target (default 17000 ≈ 1M req/min)
//   WORK_MS     simulated per-request work (default 5ms)
//   CHAIN       "1" routes through /chain (api→worker, exercises the mesh)
export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
export const TARGET_RPS = parseInt(__ENV.TARGET_RPS || '17000', 10);
export const WORK_MS = parseInt(__ENV.WORK_MS || '5', 10);

export function targetPath() {
  return __ENV.CHAIN === '1'
    ? `/chain?calls=2&ms=${WORK_MS}`
    : `/work?ms=${WORK_MS}`;
}

// The SLO, executable: p99 < 150ms, errors < 0.1%. A failed threshold fails
// the run — load tests are pass/fail, not vibes (docs/SCALING.md#method).
export const SLO_THRESHOLDS = {
  http_req_duration: ['p(99)<150'],
  http_req_failed: ['rate<0.001'],
};
