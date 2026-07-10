// Ramp: climb to TARGET_RPS in steps, hold, and watch what breaks first.
// constant-arrival-rate (open model) — unlike VU loops, it keeps offering load
// when the system slows, which is how real traffic behaves.
//
// The full 17k-RPS run needs a beefy load generator (or distributed k6);
// see docs/SCALING.md#method for generator sizing and the measurement protocol.
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, TARGET_RPS, targetPath, SLO_THRESHOLDS } from './lib.js';

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: Math.max(100, Math.floor(TARGET_RPS / 20)),
      timeUnit: '1s',
      preAllocatedVUs: 500,
      maxVUs: 20000,
      stages: [
        { target: Math.floor(TARGET_RPS * 0.25), duration: '2m' },
        { target: Math.floor(TARGET_RPS * 0.5), duration: '3m' },
        { target: Math.floor(TARGET_RPS * 0.75), duration: '3m' },
        { target: TARGET_RPS, duration: '4m' },
        { target: TARGET_RPS, duration: '10m' }, // hold at target
        { target: 0, duration: '2m' },
      ],
    },
  },
  thresholds: SLO_THRESHOLDS,
};

export default function () {
  const res = http.get(`${BASE_URL}${targetPath()}`);
  check(res, { 'status 200': (r) => r.status === 200 });
}
