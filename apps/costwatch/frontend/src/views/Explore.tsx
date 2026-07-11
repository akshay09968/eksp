import { useEffect, useState } from 'react';
import { ApiError, fetchCosts, type Granularity, type Series } from '../lib/api';
import { money, periodLabel, toCsv } from '../lib/format';
import { StackedExplore } from '../components/charts';
import { EmptyState, Skeleton } from '../components/primitives';

const GROUP_BYS = [
  { value: 'SERVICE', label: 'Service' },
  { value: 'REGION', label: 'Region' },
  { value: 'USAGE_TYPE', label: 'Usage type' },
  { value: 'LINKED_ACCOUNT', label: 'Account' },
  { value: 'RESOURCE_ID', label: 'Resource' },
];

const RANGES: Record<Granularity, { days: number; label: string }[]> = {
  HOURLY: [
    { days: 1, label: '24 hours' },
    { days: 3, label: '3 days' },
    { days: 14, label: '14 days' },
  ],
  DAILY: [
    { days: 14, label: '14 days' },
    { days: 30, label: '30 days' },
    { days: 90, label: '90 days' },
  ],
  MONTHLY: [
    { days: 180, label: '6 months' },
    { days: 390, label: '13 months' },
  ],
};

export default function Explore() {
  const [granularity, setGranularity] = useState<Granularity>('DAILY');
  const [groupBy, setGroupBy] = useState('SERVICE');
  const [days, setDays] = useState(30);
  const [series, setSeries] = useState<Series | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [showTable, setShowTable] = useState(false);

  useEffect(() => {
    let live = true;
    setSeries(null);
    setError(null);
    fetchCosts(granularity, groupBy, days)
      .then((s) => live && setSeries(s))
      .catch((e) => live && setError(e instanceof ApiError ? e : new ApiError(0, String(e))));
    return () => {
      live = false;
    };
  }, [granularity, groupBy, days]);

  const pickGranularity = (g: Granularity) => {
    setGranularity(g);
    setDays(RANGES[g][RANGES[g].length - 1].days);
  };

  const exportCsv = () => {
    if (!series) return;
    const blob = new Blob([toCsv(series.times, series.groups)], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `costwatch-${granularity.toLowerCase()}-${groupBy.toLowerCase()}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  return (
    <div className="card rise">
      <div className="controls">
        <div className="segmented" role="tablist" aria-label="granularity">
          {(['HOURLY', 'DAILY', 'MONTHLY'] as Granularity[]).map((g) => (
            <button key={g} className={granularity === g ? 'on' : ''} onClick={() => pickGranularity(g)}>
              {g.toLowerCase()}
            </button>
          ))}
        </div>

        <select className="control" value={groupBy} onChange={(e) => setGroupBy(e.target.value)} aria-label="group by">
          {GROUP_BYS.map((g) => (
            <option key={g.value} value={g.value}>
              by {g.label}
            </option>
          ))}
        </select>

        <select className="control" value={days} onChange={(e) => setDays(Number(e.target.value))} aria-label="range">
          {RANGES[granularity].map((r) => (
            <option key={r.days} value={r.days}>
              {r.label}
            </option>
          ))}
        </select>

        <span className="push" />
        <button className={`ghost-btn ${showTable ? 'on' : ''}`} onClick={() => setShowTable(!showTable)}>
          table
        </button>
        <button className="ghost-btn" onClick={exportCsv} disabled={!series}>
          csv ↓
        </button>
      </div>

      {error ? (
        error.status === 409 ? (
          <EmptyState glyph="◔" title="Hourly data isn't enabled on this account">
            {error.hint} — until then, <code>daily</code> has you covered.
          </EmptyState>
        ) : (
          <EmptyState glyph="▲" title={error.message}>
            {error.hint ?? 'Retry, or check the backend logs.'}
          </EmptyState>
        )
      ) : series ? (
        series.groups.length === 0 ? (
          <EmptyState glyph="∅" title="No cost data in this window">
            New accounts take ~24h to produce Cost Explorer data.
          </EmptyState>
        ) : showTable ? (
          <table className="data">
            <thead>
              <tr>
                <th>Period</th>
                {series.groups.map((g) => (
                  <th className="num" key={g.key}>
                    {g.key}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {series.times.map((t, i) => (
                <tr key={t}>
                  <td>{periodLabel(t)}</td>
                  {series.groups.map((g) => (
                    <td className="num" key={g.key}>
                      {money(g.values[i] ?? 0)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <StackedExplore series={series} />
        )
      ) : (
        <Skeleton />
      )}

      {series && (
        <div className="footnote">
          total {money(series.total)} · {series.cached ? 'cached' : 'fresh'} · fetched from Cost Explorer{' '}
          {series.cached ? '(6h TTL — CE bills per call)' : 'just now'}
        </div>
      )}
    </div>
  );
}
