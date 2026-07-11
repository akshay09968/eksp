import { describe, expect, it } from 'vitest';
import { money, pct, periodLabel, toCsv } from './format';

describe('money', () => {
  it('shows cents under $1000 and whole dollars above', () => {
    expect(money(3.456)).toBe('$3.46');
    expect(money(999.99)).toBe('$999.99');
    expect(money(1234.56)).toBe('$1,235');
  });

  it('handles negatives (credits/refunds)', () => {
    expect(money(-42.5)).toBe('-$42.50');
  });
});

describe('pct', () => {
  it('signs increases explicitly — a cost delta must never look ambiguous', () => {
    expect(pct(12.34)).toBe('+12.3%');
    expect(pct(-8)).toBe('-8.0%');
    expect(pct(0)).toBe('0.0%');
  });
});

describe('periodLabel', () => {
  it('renders CE date periods as short days', () => {
    expect(periodLabel('2026-07-03')).toBe('Jul 3');
  });

  it('renders hourly periods with UTC time (matches CE bucketing)', () => {
    expect(periodLabel('2026-07-10T14:00:00Z')).toBe('Jul 10 14:00');
  });

  it('passes through garbage unchanged instead of NaN-ing the axis', () => {
    expect(periodLabel('not-a-date')).toBe('not-a-date');
  });
});

describe('toCsv', () => {
  it('quotes keys containing commas/quotes (service names have both)', () => {
    const csv = toCsv(
      ['2026-07-01'],
      [{ key: 'EC2 - Other, "misc"', values: [1.5] }],
    );
    const [header, row] = csv.split('\n');
    expect(header).toBe('period,"EC2 - Other, ""misc"""');
    expect(row).toBe('2026-07-01,1.5000');
  });

  it('zero-fills missing values so columns stay aligned', () => {
    const csv = toCsv(
      ['2026-07-01', '2026-07-02'],
      [{ key: 'S3', values: [2] }],
    );
    expect(csv.split('\n')[2]).toBe('2026-07-02,0.0000');
  });
});
