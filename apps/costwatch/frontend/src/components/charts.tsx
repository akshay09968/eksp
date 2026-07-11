// Chart components on Recharts, wired to the dataviz method: thin marks, one
// axis, hairline grid, entity-stable colors, hover layer everywhere.
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import type { Series } from '../lib/api';
import { money, periodLabel } from '../lib/format';
import { chrome, seriesColor, useTheme } from '../theme';
import { ChartTooltip, Legend } from './primitives';

function toRows(series: Series): Record<string, number | string>[] {
  return series.times.map((t, i) => {
    const row: Record<string, number | string> = { period: periodLabel(t) };
    for (const g of series.groups) row[g.key] = g.values[i] ?? 0;
    return row;
  });
}

const axisStyle = (axis: string) => ({
  fontSize: 10.5,
  fontFamily: "'IBM Plex Mono', monospace",
  fill: axis,
});

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function tooltipContent(mode: 'light' | 'dark') {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return ({ active, payload, label }: any) => {
    if (!active || !payload?.length) return null;
    return (
      <ChartTooltip
        label={String(label ?? '')}
        rows={payload.map((p: { name: string; value: number }) => ({
          name: p.name,
          value: p.value,
          color: seriesColor(p.name, mode),
        }))}
      />
    );
  };
}

// Total spend over time — single series, so a quiet one-hue area.
export function TrendChart(props: { series: Series; height?: number }) {
  const mode = useTheme();
  const c = chrome(mode);
  const accent = seriesColor(props.series.groups[0]?.key ?? 'total', mode);

  const rows = props.series.times.map((t, i) => ({
    period: periodLabel(t),
    total: props.series.groups.reduce((sum, g) => sum + (g.values[i] ?? 0), 0),
  }));

  return (
    <ResponsiveContainer width="100%" height={props.height ?? 240}>
      <AreaChart data={rows} margin={{ top: 6, right: 4, left: 4, bottom: 0 }}>
        <CartesianGrid stroke={c.grid} strokeWidth={1} vertical={false} />
        <XAxis dataKey="period" tick={axisStyle(c.axis)} tickLine={false} stroke={c.baseline} minTickGap={28} />
        <YAxis tick={axisStyle(c.axis)} tickLine={false} axisLine={false} tickFormatter={(v: number) => money(v)} width={64} />
        <Tooltip content={tooltipContent(mode)} cursor={{ stroke: c.baseline }} />
        <Area type="monotone" dataKey="total" name="Total" stroke={accent} strokeWidth={2} fill={accent} fillOpacity={0.09} />
      </AreaChart>
    </ResponsiveContainer>
  );
}

// Share of spend — donut, top slices direct-labeled via legend alongside.
export function BreakdownDonut(props: { series: Series; height?: number }) {
  const mode = useTheme();
  const data = props.series.groups.map((g) => ({ name: g.key, value: g.total }));

  return (
    <>
      <ResponsiveContainer width="100%" height={props.height ?? 210}>
        <PieChart>
          <Pie data={data} dataKey="value" nameKey="name" innerRadius="58%" outerRadius="88%" paddingAngle={1.5} stroke="var(--surface)" strokeWidth={2}>
            {data.map((d) => (
              <Cell key={d.name} fill={seriesColor(d.name, mode)} />
            ))}
          </Pie>
          <Tooltip content={tooltipContent(mode)} />
        </PieChart>
      </ResponsiveContainer>
      <Legend items={data.slice(0, 6).map((d) => ({ key: d.name, color: seriesColor(d.name, mode) }))} />
    </>
  );
}

// Explore: stacked bars per period, 2px surface gap via stroke.
export function StackedExplore(props: { series: Series; height?: number }) {
  const mode = useTheme();
  const c = chrome(mode);
  const rows = toRows(props.series);
  const keys = props.series.groups.map((g) => g.key);

  return (
    <>
      <ResponsiveContainer width="100%" height={props.height ?? 300}>
        <BarChart data={rows} margin={{ top: 6, right: 4, left: 4, bottom: 0 }}>
          <CartesianGrid stroke={c.grid} strokeWidth={1} vertical={false} />
          <XAxis dataKey="period" tick={axisStyle(c.axis)} tickLine={false} stroke={c.baseline} minTickGap={26} />
          <YAxis tick={axisStyle(c.axis)} tickLine={false} axisLine={false} tickFormatter={(v: number) => money(v)} width={64} />
          <Tooltip content={tooltipContent(mode)} cursor={{ fill: 'var(--wash)' }} />
          {keys.map((k) => (
            <Bar key={k} dataKey={k} stackId="cost" fill={seriesColor(k, mode)} stroke="var(--surface)" strokeWidth={1} maxBarSize={42} />
          ))}
        </BarChart>
      </ResponsiveContainer>
      <Legend items={keys.map((k) => ({ key: k, color: seriesColor(k, mode) }))} />
    </>
  );
}

// 14-period sparkline for table rows.
export function Sparkline(props: { values: number[]; color: string }) {
  const data = props.values.map((v, i) => ({ i, v }));
  return (
    <ResponsiveContainer width={110} height={26}>
      <LineChart data={data} margin={{ top: 3, right: 0, left: 0, bottom: 3 }}>
        <Line type="monotone" dataKey="v" stroke={props.color} strokeWidth={1.5} dot={false} />
      </LineChart>
    </ResponsiveContainer>
  );
}
