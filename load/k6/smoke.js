// Smoke: is the path even healthy? 50 RPS for 1 minute. Run this before any
// serious scenario — a failing smoke means fix the deploy, not tune the load.
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, targetPath, SLO_THRESHOLDS } from './lib.js';

export const options = {
  scenarios: {
    smoke: {
      executor: 'constant-arrival-rate',
      rate: 50,
      timeUnit: '1s',
      duration: '1m',
      preAllocatedVUs: 20,
      maxVUs: 100,
    },
  },
  thresholds: SLO_THRESHOLDS,
};

export default function () {
  const res = http.get(`${BASE_URL}${targetPath()}`);
  check(res, { 'status 200': (r) => r.status === 200 });
}
