import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';

const THEME_KEY = 'modelhike-debug-theme';

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  try { localStorage.setItem(THEME_KEY, theme); } catch (_) {}
}

function readStoredTheme() {
  try { return localStorage.getItem(THEME_KEY) || 'dark'; } catch (_) { return 'dark'; }
}

export class HeaderBar extends LitElement {
  static properties = {
    phases:  { type: Array  },
    session: { type: Object },
    _theme:  { type: String, state: true },
  };

  static styles = css`
    :host {
      display: block;
      background: var(--bg-panel, #252526);
      border-bottom: 2px solid var(--text-teal, #4ec9b0);
    }

    .header-content {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 8px 12px;
      flex-wrap: wrap;
    }

    h1 {
      margin: 0;
      font-size: 15px;
      font-weight: 700;
      color: var(--text-teal, #4ec9b0);
      letter-spacing: -0.01em;
      white-space: nowrap;
    }

    /* Phase pills */
    .phases {
      display: flex;
      gap: 4px;
      flex-wrap: wrap;
    }

    .phase {
      padding: 3px 8px;
      background: var(--bg-badge, #2d2d2d);
      border-radius: var(--radius, 4px);
      font-size: 10px;
      color: var(--text-dim, #a0a0a0);
      letter-spacing: 0.02em;
      transition: background 0.1s;
    }

    .phase.done   { background: #0e639c; color: #ffffffcc; }
    .phase.failed { background: #6c1f1f; color: var(--clr-error, #f48771); }

    /* Right-side stats + controls */
    .right {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-left: auto;
      flex-wrap: wrap;
    }

    .summary {
      display: flex;
      gap: 8px;
      font-size: 11px;
      color: var(--text-dim, #858585);
    }

    .summary-item { display: flex; align-items: center; gap: 3px; }
    .summary-value { color: var(--text, #c5c5c5); font-weight: 500; }

    /* Theme toggle */
    .theme-btn {
      background: var(--bg-input, #3c3c3c);
      border: 1px solid var(--border, #444);
      border-radius: var(--radius-pill, 999px);
      color: var(--text-dim, #a0a0a0);
      cursor: pointer;
      font: inherit;
      font-size: 13px;
      line-height: 1;
      padding: 4px 8px;
      display: flex;
      align-items: center;
      gap: 4px;
      transition: background 0.1s, color 0.1s;
    }

    .theme-btn:hover {
      background: var(--bg-hover, #4c4c4c);
      color: var(--text, #d4d4d4);
    }

    .theme-label {
      font-size: 10px;
      letter-spacing: 0.04em;
      text-transform: uppercase;
    }
  `;

  constructor() {
    super();
    this.phases  = [];
    this.session = null;
    this._theme  = readStoredTheme();
    // Apply persisted theme immediately on construction
    applyTheme(this._theme);
  }

  _toggleTheme() {
    this._theme = this._theme === 'dark' ? 'light' : 'dark';
    applyTheme(this._theme);
  }

  render() {
    const eventCount = this.session?.events?.length ?? 0;
    const fileCount  = this.session?.files?.length  ?? 0;
    const errorCount = (this.session?.errors?.length ?? 0)
      + (this.session?.events ?? []).filter(ev => {
          const t = Object.keys(ev.event)[0];
          return t === 'error' || (t === 'diagnostic' && (ev.event?.diagnostic?.severity === 'error'));
        }).length;

    const isDark = this._theme !== 'light';

    return html`
      <div class="header-content">
        <h1>ModelHike Debug</h1>

        <div class="phases">
          ${this.phases.map(p => html`
            <span class="phase ${p.success ? 'done' : ''} ${(!p.success && p.completedAt) ? 'failed' : ''}">
              ${p.name}
            </span>
          `)}
        </div>

        <div class="right">
          <div class="summary">
            <span class="summary-item">
              Events:&nbsp;<span class="summary-value">${eventCount.toLocaleString()}</span>
            </span>
            <span class="summary-item">
              Files:&nbsp;<span class="summary-value">${fileCount.toLocaleString()}</span>
            </span>
            ${errorCount > 0 ? html`
              <span class="summary-item" style="color: var(--clr-error, #f48771)">
                ❌&nbsp;<span class="summary-value" style="color: var(--clr-error, #f48771)">${errorCount}</span>
              </span>
            ` : ''}
          </div>

          <button
            class="theme-btn"
            title="${isDark ? 'Switch to light theme' : 'Switch to dark theme'}"
            @click="${this._toggleTheme}"
          >
            <span>${isDark ? '☀️' : '🌙'}</span>
            <span class="theme-label">${isDark ? 'Light' : 'Dark'}</span>
          </button>
        </div>
      </div>
    `;
  }
}

customElements.define('header-bar', HeaderBar);
