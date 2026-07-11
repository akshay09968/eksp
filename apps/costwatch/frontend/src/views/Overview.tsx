import { useEffect, useState } from 'react';
import { ApiError, fetchCosts, fetchSummary, type Series, type Summary } from '../lib/api';
import { money, pct } from '../lib/format';
import { seriesColor, useTheme } from '../theme';
import { BreakdownDonut, TrendChart } from '../components/charts';
import { EmptyState, KpiTile, Skeleton } from '../components/primitives';

export default function Overview() {
  const mode = useTheme();
  const [summary, setSummary] = useState<Summary | null>(null);
  const [trend, setTrend] = useState<Series | null>(null);
  const [monthly, setMonthly] = useState<Series | null>(null);
  const [error, setError] = useState<ApiError | null>(null);

  useEffect(() => {
    let live = true;
    Promise.all([fetchSummary(), fetchCosts('DAILY', 'SERVICE', 30), fetchCosts('MONTHLY', 'SERVICE', 30)])
      .then(([s, t, m]) => {
        if (!live) return;
        setSummary(s);
        setTrend(t);
        setMonthly(m);
      })
      .catch((e) => live && setError(e instanceof ApiError ? e : new ApiError(0, String(e))));
    return () => {
      live = false;
    };
  }, []);

  if (error) {
    return (
      <div className="card">
        <EmptyState glyph="▲" title={error.message}>
          {error.hint ?? 'Check the backend logs (`kubectl -n costwatch logs deploy/costwatch`).'}
        </EmptyState>
      </div>
    );
  }

  const topMover = summary?.topMovers[0];

  return (
    <>
      <div className="grid kpis" style={{ marginBottom: 14 }}>
        <KpiTile label="Month to date" value={summary ? money(summary.monthToDate) : '—'} sub="unblended, this account" />
        <KpiTile label="Forecast · month end" value={summary ? money(summary.forecastMonthEnd) : '—'} sub="Cost Explorer projection" />
        <KpiTile
          label="vs same days last month"
          value={summary ? pct(summary.deltaPct) : '—'}
          sub={
            summary && (
              <span className={summary.deltaPct > 0 ? 'delta-up' : 'delta-down'}>
                {summary.deltaPct > 0 ? '▲ spending more' : '▼ spending less'}
              </span>
            )
          }
        />
        <KpiTile
          label="Top mover"
          value={topMover ? money(topMover.delta) : '—'}
          sub={topMover ? `${topMover.service}` : 'no movement'}
        />
      </div>

      <div className="grid two-col">
        <div className="card rise">
          <h3>Daily spend · last 30 days</h3>
          {trend ? <TrendChart series={trend} /> : <Skeleton />}
        </div>
        <div className="card rise">
          <h3>Share by service · this period</h3>
          {monthly ? <BreakdownDonut series={monthly} /> : <Skeleton />}
        </div>
      </div>

      {summary && summary.topMovers.length > 1 && (
        <div className="card rise" style={{ marginTop: 14 }}>
          <h3>Movers · vs same window last month</h3>
          <table className="data">
            <thead>
              <tr>
                <th>Service</th>
                <th className="num">Previous</th>
                <th className="num">Current</th>
                <th className="num">Δ</th>
              </tr>
            </thead>
            <tbody>
              {summary.topMovers.map((m) => (
                <tr key={m.service}>
                  <td>
                    <span className="l-swatch" style={{ background: seriesColor(m.service, mode), display: 'inline-block', marginRight: 8, width: 9, height: 9, borderRadius: 2 }} />
                    {m.service}
                  </td>
                  <td className="num">{money(m.previous)}</td>
                  <td className="num">{money(m.current)}</td>
                  <td className="num">
                    <span className={m.delta > 0 ? 'delta-up' : 'delta-down'}>
                      {m.delta > 0 ? '+' : ''}
                      {money(m.delta)}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
