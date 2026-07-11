const usd = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 2,
});

const usdWhole = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 0,
});

export function money(v: number): string {
  if (Math.abs(v) >= 1000) return usdWhole.format(v);
  return usd.format(v);
}

export function pct(v: number): string {
  const sign = v > 0 ? '+' : '';
  return `${sign}${v.toFixed(1)}%`;
}

// Period label: "2026-07-03" → "Jul 3" · "2026-07-10T14:00:00Z" → "Jul 10 14:00"
export function periodLabel(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const day = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
  if (iso.includes('T')) {
    const hm = d.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
      timeZone: 'UTC',
    });
    return `${day} ${hm}`;
  }
  return day;
}

export function relativeTime(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const min = Math.floor(ms / 60_000);
  if (min < 1) return 'just now';
  if (min < 60) return `${min}m ago`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

export function toCsv(times: string[], groups: { key: string; values: number[] }[]): string {
  const header = ['period', ...groups.map((g) => `"${g.key.replaceAll('"', '""')}"`)].join(',');
  const rows = times.map((t, i) =>
    [t, ...groups.map((g) => (g.values[i] ?? 0).toFixed(4))].join(','),
  );
  return [header, ...rows].join('\n');
}
