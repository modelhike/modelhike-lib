import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { eventType, eventPayload, escapeHtml } from '../utils/formatters.js';

/**
 * problems-panel — shows errors and diagnostics from /api/diagnostics (preferred)
 * or falls back to filtering the event trace passed via `.events`.
 *
 * Usage: <problems-panel .events=${allEvents}></problems-panel>
 *
 * Each problem row shows:
 *   [icon] [code] message
 *            file:line
 *   ↳ suggestion (if present)
 */
export class ProblemsPanel extends LitElement {
  static properties = {
    events: { type: Array },
    _filter: { type: String, state: true },
    _apiDiagnostics: { type: Array, state: true },
  };

  static styles = css`
    :host {
      display: flex;
      flex-direction: column;
      height: 100%;
      background: var(--bg-app, #1e1e1e);
      color: var(--text, #d4d4d4);
      font-family: ui-monospace, 'Menlo', 'Consolas', monospace;
      font-size: 12px;
      overflow: hidden;
    }

    .toolbar {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 6px 10px;
      background: var(--bg-panel-alt, #202123);
      border-bottom: 1px solid var(--border, #333);
      flex-shrink: 0;
    }

    .toolbar input {
      flex: 1;
      background: var(--bg-input, #3c3c3c);
      border: 1px solid var(--border, #444);
      border-radius: var(--radius, 4px);
      color: var(--text, #d4d4d4);
      font-size: 11px;
      padding: 3px 6px;
      outline: none;
      font-family: inherit;
      transition: border-color 0.1s;
    }
    .toolbar input:focus { border-color: var(--text-teal, #4ec9b0); }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 3px;
      padding: 1px 6px;
      border-radius: var(--radius-pill, 999px);
      font-size: 11px;
      font-weight: 600;
      white-space: nowrap;
    }

    .badge--error   { background: rgba(244,135,113,.15); color: var(--clr-error,   #f48771); }
    .badge--warning { background: rgba(204,167,  0,.15); color: var(--clr-warning, #cca700); }
    .badge--info    { background: rgba( 79,193,255,.15); color: var(--clr-info,    #4fc1ff); }

    .list {
      flex: 1;
      overflow-y: auto;
    }
    .list::-webkit-scrollbar        { width: 6px; }
    .list::-webkit-scrollbar-track  { background: var(--bg-app, #1e1e1e); }
    .list::-webkit-scrollbar-thumb  { background: #424242; border-radius: 3px; }

    .empty {
      padding: 24px;
      text-align: center;
      color: var(--text-green, #6a9955);
      font-size: 13px;
    }

    .problem {
      display: grid;
      grid-template-columns: 20px 1fr;
      gap: 2px 8px;
      padding: 6px 10px;
      border-bottom: 1px solid var(--border-subtle, #2a2a2a);
      cursor: pointer;
      transition: background 0.08s;
    }

    .problem:hover { background: var(--bg-hover, #2a2d2e); }
    .problem:last-child { border-bottom: none; }

    .icon { grid-row: 1 / 3; align-self: start; padding-top: 1px; font-size: 14px; }

    .message {
      font-size: 11px;
      color: var(--text, #d4d4d4);
      word-break: break-word;
    }

    .message .code {
      color: var(--text-accent, #9cdcfe);
      margin-right: 4px;
      font-weight: 600;
    }

    .location {
      font-size: 10px;
      color: var(--text-dim, #858585);
    }

    .suggestions {
      grid-column: 2;
      margin-top: 4px;
      padding: 4px 8px;
      background: var(--bg-panel, #252526);
      border-left: 2px solid var(--border, #555);
      border-radius: 0 var(--radius, 3px) var(--radius, 3px) 0;
    }

    .suggestion-line {
      color: var(--text-accent, #9cdcfe);
      font-size: 11px;
      margin-top: 2px;
    }

    .suggestion-line::before { content: '→ '; color: var(--text-dim, #858585); }

    /* severity-based row tints */
    .problem--error   .message { color: var(--clr-error,   #f48771); }
    .problem--warning .message { color: var(--clr-warning, #cca700); }
    .problem--info    .message { color: var(--clr-info,    #4fc1ff); }
    .problem--hint    .message { color: var(--clr-hint,    #b5cea8); }
  `;

  constructor() {
    super();
    this.events = [];
    this._filter = '';
    this._apiDiagnostics = null; // null = not yet loaded; [] = loaded but empty
  }

  _handleProblemClick(problem) {
    if (problem?.eventIndex == null) return;
    this.dispatchEvent(new CustomEvent('problem-selected', {
      detail: {
        eventIndex: problem.eventIndex,
        location: problem.location || null,
      },
      bubbles: true,
      composed: true,
    }));
  }

  /** Fetch structured diagnostics from the dedicated API endpoint. */
  async loadDiagnostics() {
    try {
      const res = await fetch('/api/diagnostics');
      if (res.ok) {
        this._apiDiagnostics = await res.json();
      }
    } catch (_) { /* fall back to event-derived list */ }
  }

  get problems() {
    const normalizeSuggestions = (suggestions) => {
      if (!Array.isArray(suggestions)) return [];
      return suggestions.map(s => {
        if (typeof s === 'string') {
          return { kind: 'note', message: s, replacement: null, options: [] };
        }
        return {
          kind: s?.kind || 'note',
          message: s?.message || '',
          replacement: s?.replacement || null,
          options: Array.isArray(s?.options) ? s.options : [],
        };
      });
    };

    // Prefer the structured /api/diagnostics response when available
    if (Array.isArray(this._apiDiagnostics) && this._apiDiagnostics.length >= 0) {
      return this._apiDiagnostics.map(d => ({
        eventIndex: Math.max(0, (d.sequenceNo || 1) - 1),
        severity: d.severity || 'info',
        icon: d.severity === 'error' ? '❌' : d.severity === 'warning' ? '⚠️' : d.severity === 'hint' ? '💡' : 'ℹ️',
        code: d.code || null,
        message: d.message || '',
        location: (d.fileIdentifier || d.lineNo) ? { fileIdentifier: d.fileIdentifier, lineNo: d.lineNo } : null,
        suggestions: normalizeSuggestions(d.suggestions),
      }));
    }

    // Fallback: derive from events array
    if (!this.events) return [];
    const raw = this.events.map((ev, index) => ({ ev, index })).filter(({ ev }) => {
      const t = eventType(ev);
      return t === 'error' || t === 'diagnostic';
    });

    return raw.map(({ ev, index }) => {
      const t = eventType(ev);
      const v = eventPayload(ev) || {};
      if (t === 'error') {
        return {
          eventIndex: index,
          severity: 'error',
          icon: '❌',
          code: v.code || null,
          message: v.message || String(v),
          location: v.source || null,
          suggestions: [],
        };
      }
      return {
        eventIndex: index,
        severity: v.severity || 'info',
        icon: v.severity === 'error' ? '❌' : v.severity === 'warning' ? '⚠️' : v.severity === 'hint' ? '💡' : 'ℹ️',
        code: v.code || null,
        message: v.message || '',
        location: v.source || null,
        suggestions: normalizeSuggestions(v.suggestions),
      };
    });
  }

  get filteredProblems() {
    const q = (this._filter || '').toLowerCase().trim();
    if (!q) return this.problems;
    return this.problems.filter(p =>
      p.message.toLowerCase().includes(q) ||
      (p.code && p.code.toLowerCase().includes(q)) ||
      (p.location?.fileIdentifier || '').toLowerCase().includes(q)
    );
  }

  get errorCount()   { return this.problems.filter(p => p.severity === 'error').length; }
  get warningCount() { return this.problems.filter(p => p.severity === 'warning').length; }
  get infoCount()    { return this.problems.filter(p => p.severity === 'info' || p.severity === 'hint').length; }

  _locationStr(loc) {
    if (!loc) return '';
    const file = loc.fileIdentifier || '';
    const line = loc.lineNo > 0 ? `:${loc.lineNo}` : '';
    return file ? `${file}${line}` : '';
  }

  render() {
    const problems = this.filteredProblems;

    return html`
      <div class="toolbar">
        ${this.errorCount   > 0 ? html`<span class="badge badge--error">❌ ${this.errorCount}</span>` : ''}
        ${this.warningCount > 0 ? html`<span class="badge badge--warning">⚠️ ${this.warningCount}</span>` : ''}
        ${this.infoCount    > 0 ? html`<span class="badge badge--info">ℹ️ ${this.infoCount}</span>` : ''}
        <input
          type="search"
          placeholder="Filter problems…"
          .value="${this._filter}"
          @input="${e => this._filter = e.target.value}"
        />
      </div>

      <div class="list">
        ${problems.length === 0
          ? html`<div class="empty">✅ No problems detected</div>`
          : problems.map(p => html`
              <div
                class="problem problem--${p.severity}"
                tabindex="0"
                title="${p.eventIndex != null ? `Jump to event #${p.eventIndex + 1}` : 'No source event'}"
                @click=${() => this._handleProblemClick(p)}
                @keydown=${(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    this._handleProblemClick(p);
                  }
                }}
              >
                <span class="icon">${p.icon}</span>
                <div class="message">
                  ${p.code ? html`<span class="code">[${escapeHtml(p.code)}]</span>` : ''}
                  ${escapeHtml(p.message)}
                </div>
                ${p.location ? html`
                  <div class="location">${escapeHtml(this._locationStr(p.location))}</div>
                ` : ''}
                ${p.suggestions.length > 0 ? html`
                  <div class="suggestions">
                    ${p.suggestions.map(s => html`
                      <div class="suggestion-line" title="${escapeHtml(s.kind || 'note')}">${escapeHtml(s.message || '')}</div>
                    `)}
                  </div>
                ` : ''}
              </div>
            `)
        }
      </div>
    `;
  }
}

customElements.define('problems-panel', ProblemsPanel);
