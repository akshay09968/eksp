// Typed client for the costwatch backend — shapes mirror internal/costs/types.go.

export type Granularity = 'HOURLY' | 'DAILY' | 'MONTHLY';

export interface GroupSeries {
  key: string;
  values: number[];
  total: number;
}

export interface Series {
  times: string[];
  groups: GroupSeries[];
  total: number;
  currency: string;
  fetchedAt: string;
  cached: boolean;
}

export interface Mover {
  service: string;
  current: number;
  previous: number;
  delta: number;
}

export interface Summary {
  monthToDate: number;
  forecastMonthEnd: number;
  prevMonthToDate: number;
  deltaPct: number;
  currency: string;
  topMovers: Mover[];
  fetchedAt: string;
  cached: boolean;
}

export interface Health {
  status: string;
  demo: boolean;
  uptime: string;
  version: string;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public hint?: string,
  ) {
    super(message);
  }
}

async function get<T>(path: string): Promise<T> {
  const res = await fetch(path);
  if (!res.ok) {
    let msg = `${res.status}`;
    let hint: string | undefined;
    try {
      const body = await res.json();
      msg = body.error ?? msg;
      hint = body.hint;
    } catch {
      /* non-JSON error body */
    }
    throw new ApiError(res.status, msg, hint);
  }
  return res.json() as Promise<T>;
}

export const fetchSummary = () => get<Summary>('/api/summary');

export const fetchCosts = (granularity: Granularity, groupBy: string, days: number) =>
  get<Series>(
    `/api/costs?granularity=${granularity}&groupBy=${encodeURIComponent(groupBy)}&days=${days}`,
  );

export const fetchHealth = () => get<Health>('/api/health');
