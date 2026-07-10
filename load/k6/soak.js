// Soak: 60% of target for 30 minutes. Finds what ramps hide — memory creep,
// conntrack growth, spot interruptions mid-run, consolidation churn.
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, TARGET_RPS, targetPath, SLO_THRESHOLDS } from './lib.js';

export const options = {
  scenarios: {
    soak: {
      executor: 'constant-arrival-rate',
      rate: Math.floor(TARGET_RPS * 0.6),
      timeUnit: '1s',
      duration: '30m',
      preAllocatedVUs: 500,
      maxVUs: 20000,
    },
  },
  thresholds: SLO_THRESHOLDS,
};

export default function () {
  const res = http.get(`${BASE_URL}${targetPath()}`);
  check(res, { 'status 200': (r) => r.status === 200 });
}
