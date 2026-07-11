import { useEffect, useState } from 'react';
import { ApiError, fetchCosts, type Series } from '../lib/api';
import { money } from '../lib/format';
import { seriesColor, useTheme } from '../theme';
import { Sparkline } from '../components/charts';
import { EmptyState, Skeleton } from '../components/primitives';

export default function Resources() {
  const mode = useTheme();
  const [series, setSeries] = useState<Series | null>(null);
  const [error, setError] = useState<ApiError | null>(null);

  useEffect(() => {
    let live = true;
    // Per-resource data rides on the same opt-in as hourly granularity.
    fetchCosts('DAILY', 'RESOURCE_ID', 14)
      .then((s) => live && setSeries(s))
      .catch((e) => live && setError(e instanceof ApiError ? e : new ApiError(0, String(e))));
    return () => {
      live = false;
    };
  }, []);

  return (
    <div className="card rise">
      <h3>Top resources · last 14 days</h3>

      {error ? (
        <EmptyState glyph="◔" title="Resource-level data isn't enabled">
          {error.hint ??
            'Enable "Hourly and Resource Level Data" in Billing → Cost Management preferences (extra AWS charge), then come back.'}
        </EmptyState>
      ) : series ? (
        series.groups.length === 0 ? (
          <EmptyState glyph="∅" title="No resource-level rows yet">
            The opt-in takes up to 24h to start producing data.
          </EmptyState>
        ) : (
          <table className="data">
            <thead>
              <tr>
                <th>Resource</th>
                <th>Trend</th>
                <th className="num">14-day total</th>
                <th className="num">Share</th>
              </tr>
            </thead>
            <tbody>
              {series.groups.map((g) => (
                <tr key={g.key}>
                  <td className="truncate" title={g.key}>
                    {g.key}
                  </td>
                  <td>
                    <Sparkline values={g.values} color={seriesColor(g.key, mode)} />
                  </td>
                  <td className="num">{money(g.total)}</td>
                  <td className="num">{series.total > 0 ? `${((g.total / series.total) * 100).toFixed(1)}%` : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )
      ) : (
        <Skeleton />
      )}
    </div>
  );
}
