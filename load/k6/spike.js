// Spike: 3x step from steady state with no warning — the scenario that tests
// Karpenter provisioning latency + HPA reaction together. The interesting
// output is time-to-recovery of the p99, not the peak error rate.
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, TARGET_RPS, targetPath } from './lib.js';

const STEADY = Math.floor(TARGET_RPS / 3);

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: STEADY,
      timeUnit: '1s',
      preAllocatedVUs: 500,
      maxVUs: 20000,
      stages: [
        { target: STEADY, duration: '3m' }, // baseline
        { target: TARGET_RPS, duration: '10s' }, // the cliff
        { target: TARGET_RPS, duration: '8m' }, // absorb
        { target: STEADY, duration: '1m' },
        { target: STEADY, duration: '3m' }, // consolidation behavior
      ],
    },
  },
  // Looser than the SLO on purpose: a spike is allowed a brief burn; the
  // threshold catches sustained failure.
  thresholds: {
    http_req_duration: ['p(99)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const res = http.get(`${BASE_URL}${targetPath()}`);
  check(res, { 'status 200': (r) => r.status === 200 });
}
