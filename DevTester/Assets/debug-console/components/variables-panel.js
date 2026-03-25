import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { loadMemory } from '../utils/api.js';
import { escapeHtml } from '../utils/formatters.js';

export class VariablesPanel extends LitElement {
  static properties = {
    selectedIndex:  { type: Number },
    pausedState:    { type: Object },
    variables:      { type: Object,  state: true },
    loading:        { type: Boolean, state: true },
    lastLoadedIndex:{ type: Number,  state: true },
    _search:        { type: String,  state: true },
    _showSystem:    { type: Boolean, state: true },
  };

  static styles = css`
    :host {
      display: flex;
      flex-direction: column;
      height: 100%;
      overflow: hidden;
    }

    .header {
      flex-shrink: 0;
      padding: 8px 8px 4px;
      background: var(--bg-panel-alt, #202123);
      border-bottom: 1px solid var(--border, #333);
    }

    .panel-title {
      font-weight: 600;
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 0.07em;
      color: var(--text-accent, #9cdcfe);
      margin-bottom: 4px;
    }

    .panel-subtitle {
      font-size: 11px;
      color: var(--text-dim, #858585);
      margin-bottom: 6px;
    }

    .search-row {
      display: flex;
      gap: 4px;
      align-items: center;
    }

    .search-input {
      flex: 1;
      background: var(--bg-input, #3c3c3c);
      border: 1px solid var(--border, #444);
      border-radius: var(--radius, 4px);
      color: var(--text, #d4d4d4);
      font-size: 11px;
      padding: 3px 7px;
      outline: none;
      font-family: inherit;
      transition: border-color 0.1s;
    }
    .search-input:focus { border-color: var(--text-teal, #4ec9b0); }

    .sys-toggle {
      background: transparent;
      border: 1px solid var(--border, #444);
      border-radius: var(--radius, 4px);
      color: var(--text-dim, #858585);
      font-size: 10px;
      padding: 3px 6px;
      cursor: pointer;
      font-family: inherit;
      transition: border-color 0.1s, color 0.1s;
      white-space: nowrap;
    }
    .sys-toggle.active,
    .sys-toggle:hover { color: var(--text-accent, #9cdcfe); border-color: var(--text-accent, #9cdcfe); }

    /* ── Scrollable body ── */
    .body {
      flex: 1;
      overflow-y: auto;
      padding: 6px 0;
    }

    .body::-webkit-scrollbar        { width: 6px; }
    .body::-webkit-scrollbar-track  { background: var(--bg-app, #1e1e1e); }
    .body::-webkit-scrollbar-thumb  { background: #424242; border-radius: 3px; }
    .body::-webkit-scrollbar-thumb:hover { background: #666; }

    /* ── States ── */
    .loading-msg,
    .empty-msg {
      padding: 16px;
      font-size: 11px;
      color: var(--text-dim, #858585);
      line-height: 1.5;
    }

    /* ── Variable table ── */
    .vars-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 11px;
    }

    .vars-table th {
      position: sticky;
      top: 0;
      background: var(--bg-panel-alt, #202123);
      color: var(--text-dim, #858585);
      font-weight: 500;
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      padding: 4px 8px;
      border-bottom: 1px solid var(--border, #333);
      text-align: left;
    }

    .vars-table tr:hover td { background: var(--bg-hover, #2a2d2e); }

    .vars-table td {
      padding: 4px 8px;
      border-bottom: 1px solid var(--border-subtle, #2a2a2a);
      vertical-align: top;
    }

    .var-name {
      color: var(--text-accent, #9cdcfe);
      font-weight: 500;
      white-space: nowrap;
    }

    .var-name.system {
      color: var(--text-dim, #858585);
      font-style: italic;
    }

    .var-value {
      color: var(--text-string, #ce9178);
      max-width: 200px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .no-match {
      padding: 12px 8px;
      font-size: 11px;
      color: var(--text-dim, #858585);
      text-align: center;
    }

    /* ── Section divider ── */
    .section-header {
      padding: 5px 8px 3px;
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: var(--text-dim, #858585);
      border-top: 1px solid var(--border-subtle, #2a2a2a);
      margin-top: 4px;
    }
  `;

  constructor() {
    super();
    this.variables       = null;
    this.loading         = false;
    this.lastLoadedIndex = -1;
    this._search         = '';
    this._showSystem     = false;
  }

  async updated(changedProperties) {
    if (changedProperties.has('selectedIndex') && this.selectedIndex !== this.lastLoadedIndex) {
      await this._loadVariables();
    }
  }

  async _loadVariables() {
    if (this.selectedIndex == null) return;
    this.loading         = true;
    this.lastLoadedIndex = this.selectedIndex;
    try {
      this.variables = await loadMemory(this.selectedIndex);
    } catch (err) {
      console.error('Failed to load variables:', err);
      this.variables = null;
    } finally {
      this.loading = false;
    }
  }

  render() {
    const displayVars = this.pausedState?.vars ?? this.variables;
    const isPaused    = !!this.pausedState?.vars;

    const subtitle = isPaused
      ? `⏸ ${this.pausedState?.location?.fileIdentifier || '?'}:${this.pausedState?.location?.lineNo || '?'}`
      : `Event #${this.selectedIndex != null ? this.selectedIndex + 1 : '—'}`;

    return html`
      <div class="header">
        <div class="panel-title">Variables</div>
        <div class="panel-subtitle">${subtitle}</div>
        <div class="search-row">
          <input
            class="search-input"
            type="search"
            placeholder="Filter variables…"
            .value="${this._search}"
            @input="${e => this._search = e.target.value}"
          />
          <button
            class="sys-toggle ${this._showSystem ? 'active' : ''}"
            title="Show/hide @system variables"
            @click="${() => this._showSystem = !this._showSystem}"
          >@sys</button>
        </div>
      </div>

      <div class="body">
        ${this._renderBody(displayVars, isPaused)}
      </div>
    `;
  }

  _renderBody(displayVars, isPaused) {
    if (this.loading && !isPaused) {
      return html`<div class="loading-msg">Loading…</div>`;
    }

    if (!displayVars) {
      return html`
        <div class="empty-msg">
          Variables are captured when files are generated.<br>
          Select an event after file generation begins.
        </div>
      `;
    }

    const q = (this._search || '').toLowerCase().trim();
    const entries = Object.entries(displayVars);

    const userVars = entries.filter(([k]) => !k.startsWith('@'));
    const sysVars  = entries.filter(([k]) => k.startsWith('@'));

    const filterFn = ([k, v]) => !q || k.toLowerCase().includes(q) || String(v).toLowerCase().includes(q);

    const filteredUser = userVars.filter(filterFn).sort(([a], [b]) => a.localeCompare(b));
    const filteredSys  = this._showSystem ? sysVars.filter(filterFn).sort(([a], [b]) => a.localeCompare(b)) : [];

    if (filteredUser.length === 0 && filteredSys.length === 0) {
      return html`<div class="no-match">No variables match "${escapeHtml(q)}"</div>`;
    }

    return html`
      <table class="vars-table">
        <tr>
          <th>Variable</th>
          <th>Value</th>
        </tr>
        ${filteredUser.map(([k, v]) => this._row(k, v, false))}
        ${filteredSys.length > 0 ? html`
          <tr><td colspan="2" class="section-header">@system</td></tr>
          ${filteredSys.map(([k, v]) => this._row(k, v, true))}
        ` : ''}
      </table>
    `;
  }

  _row(k, v, isSystem) {
    const val = String(v ?? '');
    return html`
      <tr>
        <td class="var-name ${isSystem ? 'system' : ''}">${escapeHtml(k)}</td>
        <td class="var-value" title="${escapeHtml(val)}">${escapeHtml(val)}</td>
      </tr>
    `;
  }
}

customElements.define('variables-panel', VariablesPanel);
