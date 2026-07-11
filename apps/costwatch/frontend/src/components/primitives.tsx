// Small shared pieces: KPI tile, tooltip, legend, empty/error states.
import type { ReactNode } from 'react';
import { money } from '../lib/format';

export function KpiTile(props: { label: string; value: string; sub?: ReactNode }) {
  return (
    <div className="card kpi rise">
      <h3>{props.label}</h3>
      <div className="value">{props.value}</div>
      {props.sub && <div className="sub">{props.sub}</div>}
    </div>
  );
}

export interface TooltipRow {
  name: string;
  value: number;
  color: string;
}

// One tooltip for every chart: label + swatch rows, values right-aligned mono.
export function ChartTooltip(props: { label?: string; rows: TooltipRow[] }) {
  if (props.rows.length === 0) return null;
  const rows = [...props.rows].sort((a, b) => b.value - a.value).slice(0, 10);
  return (
    <div className="tooltip">
      {props.label && <div className="t-label">{props.label}</div>}
      {rows.map((r) => (
        <div className="t-row" key={r.name}>
          <span className="t-swatch" style={{ background: r.color }} />
          <span>{r.name}</span>
          <span className="t-val">{money(r.value)}</span>
        </div>
      ))}
    </div>
  );
}

export function Legend(props: { items: { key: string; color: string }[] }) {
  if (props.items.length < 2) return null; // single series needs no legend box
  return (
    <div className="legend">
      {props.items.map((it) => (
        <span className="l-item" key={it.key}>
          <span className="l-swatch" style={{ background: it.color }} />
          {it.key}
        </span>
      ))}
    </div>
  );
}

export function EmptyState(props: { glyph: string; title: string; children: ReactNode }) {
  return (
    <div className="state">
      <span className="glyph">{props.glyph}</span>
      <h4>{props.title}</h4>
      <p>{props.children}</p>
    </div>
  );
}

export function Skeleton() {
  return <div className="skeleton" />;
}
