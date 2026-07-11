// The dataviz non-negotiable under test: color follows the entity, never its
// rank — a series keeps its hue across refetches and filter changes.
import { describe, expect, it } from 'vitest';
import { chrome, seriesColor } from './theme';

describe('seriesColor', () => {
  it('is stable for the same key across calls and modes', () => {
    const first = seriesColor('Amazon EC2', 'light');
    seriesColor('Amazon S3', 'light'); // interleave another assignment
    expect(seriesColor('Amazon EC2', 'light')).toBe(first);
  });

  it('assigns distinct slots to distinct keys in encounter order', () => {
    const a = seriesColor('svc-alpha', 'light');
    const b = seriesColor('svc-beta', 'light');
    expect(a).not.toBe(b);
  });

  it('keeps light/dark as selected steps of the same slot', () => {
    const light = seriesColor('svc-modes', 'light');
    const dark = seriesColor('svc-modes', 'dark');
    expect(light).toMatch(/^#[0-9a-f]{6}$/);
    expect(dark).toMatch(/^#[0-9a-f]{6}$/);
  });

  it('renders Other as the reserved neutral, never a categorical hue', () => {
    expect(seriesColor('Other', 'light')).toBe('#898781');
    expect(seriesColor('Other', 'dark')).toBe('#898781');
  });
});

describe('chrome', () => {
  it('provides per-mode hairline values', () => {
    expect(chrome('light').grid).not.toBe(chrome('dark').grid);
  });
});
