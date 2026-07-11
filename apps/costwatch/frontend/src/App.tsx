import { useEffect, useState } from 'react';
import { fetchHealth, type Health } from './lib/api';
import { relativeTime } from './lib/format';
import { toggleTheme, useTheme } from './theme';
import Overview from './views/Overview';
import Explore from './views/Explore';
import Resources from './views/Resources';

type View = 'overview' | 'explore' | 'resources';

const VIEWS: { id: View; label: string }[] = [
  { id: 'overview', label: 'Overview' },
  { id: 'explore', label: 'Explore' },
  { id: 'resources', label: 'Resources' },
];

function viewFromHash(): View {
  const h = location.hash.replace('#/', '');
  return (VIEWS.find((v) => v.id === h)?.id ?? 'overview') as View;
}

export default function App() {
  const mode = useTheme();
  const [view, setView] = useState<View>(viewFromHash);
  const [health, setHealth] = useState<Health | null>(null);
  const [loadedAt] = useState(() => new Date().toISOString());

  useEffect(() => {
    fetchHealth().then(setHealth).catch(() => setHealth(null));
    const onHash = () => setView(viewFromHash());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  const nav = (v: View) => {
    location.hash = `/${v}`;
    setView(v);
  };

  return (
    <>
      <header className="masthead">
        <span className="wordmark">costwatch</span>
        <span className="tagline">AWS spend, traced — hourly to monthly, service to resource</span>
        <span className="spacer" />
        {health?.demo && <span className="badge demo">demo data</span>}
        <span className="badge fresh" title={`page loaded ${loadedAt}`}>
          {relativeTime(loadedAt)}
        </span>
        <button className="theme-toggle" onClick={toggleTheme} aria-label="toggle theme">
          {mode === 'dark' ? '◐ light' : '◑ dark'}
        </button>
      </header>

      <nav className="tabs" aria-label="views">
        {VIEWS.map((v) => (
          <button key={v.id} className={`tab ${view === v.id ? 'active' : ''}`} onClick={() => nav(v.id)}>
            {v.label}
          </button>
        ))}
      </nav>

      {view === 'overview' && <Overview />}
      {view === 'explore' && <Explore />}
      {view === 'resources' && <Resources />}

      <div className="footnote">
        read-only against Cost Explorer via EKS Pod Identity · cache TTL 6h (CE bills ~$0.01/call) ·{' '}
        {health ? `backend ${health.version} up ${health.uptime}` : 'backend unreachable'}
      </div>
    </>
  );
}
