// Theme state + the dataviz reference palette (see docs: dataviz skill,
// references/palette.md). Both modes are hand-selected steps, not auto-flips.

import { useSyncExternalStore } from 'react';

export type Mode = 'light' | 'dark';

const listeners = new Set<() => void>();

function currentMode(): Mode {
  return document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
}

export function toggleTheme(): void {
  const next: Mode = currentMode() === 'dark' ? 'light' : 'dark';
  if (next === 'dark') {
    document.documentElement.dataset.theme = 'dark';
  } else {
    delete document.documentElement.dataset.theme;
  }
  localStorage.setItem('costwatch-theme', next);
  listeners.forEach((l) => l());
}

export function useTheme(): Mode {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    currentMode,
    () => 'light',
  );
}

// Categorical slots — fixed order, never cycled (CVD-safe ordering is the
// mechanism, not cosmetics). Series 9+ folds into "Other" server-side.
const CATEGORICAL: Record<Mode, string[]> = {
  light: ['#2a78d6', '#1baf7a', '#eda100', '#008300', '#4a3aa7', '#e34948', '#e87ba4', '#eb6834'],
  dark: ['#3987e5', '#199e70', '#c98500', '#008300', '#9085e9', '#e66767', '#d55181', '#d95926'],
};

const OTHER: Record<Mode, string> = { light: '#898781', dark: '#898781' };

// Color follows the entity: a key keeps its slot for the whole session even if
// filters change the visible set.
const slotByKey = new Map<string, number>();

export function seriesColor(key: string, mode: Mode): string {
  if (key === 'Other') return OTHER[mode];
  let slot = slotByKey.get(key);
  if (slot === undefined) {
    slot = slotByKey.size % CATEGORICAL[mode].length;
    slotByKey.set(key, slot);
  }
  return CATEGORICAL[mode][slot];
}

export const chrome = (mode: Mode) =>
  mode === 'dark'
    ? { grid: '#2c2c2a', axis: '#898781', baseline: '#383835' }
    : { grid: '#e1e0d9', axis: '#898781', baseline: '#c3c2b7' };
