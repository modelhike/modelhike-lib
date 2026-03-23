import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { loadMemory } from '../utils/api.js';
import { escapeHtml } from '../utils/formatters.js';

export class VariablesPanel extends LitElement {
  static properties = {
    selectedIndex: { type: Number },
    pausedState: { type: Object },  // stepping mode: { location, vars }
    variables: { type: Object, state: true },
    loading: { type: Boolean, state: true },
    lastLoadedIndex: { type: Number, state: true }
  };

  static styles = css`
    :host {
      display: block;
      height: 100%;
      overflow: auto;
      padding: 8px;
    }

    .panel-title {
      font-weight: 600;
      margin-bottom: 8px;
      color: #9cdcfe;
    }

    .panel-subtitle {
      font-size: 11px;
      color: #858585;
      margin-bottom: 8px;
    }

    .vars-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 12px;
    }

    .vars-table th,
    .vars-table td {
      padding: 4px 8px;
      text-align: left;
      border-bottom: 1px solid #333;
    }

    .vars-table th {
      color: #858585;
      font-weight: 500;
    }

    .var-name {
      color: #9cdcfe;
      font-weight: 500;
    }

    .var-value {
      color: #ce9178;
      max-width: 200px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    em {
      color: #858585;
    }
  `;

  constructor() {
    super();
    this.variables = null;
    this.loading = false;
    this.lastLoadedIndex = -1;
  }

  async updated(changedProperties) {
    if (changedProperties.has('selectedIndex') && this.selectedIndex !== this.lastLoadedIndex) {
      await this.loadVariables();
    }
  }

  async loadVariables() {
    if (this.selectedIndex === undefined || this.selectedIndex === null) return;
    
    this.loading = true;
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
    // Prioritize showing paused state variables when stepping
    const displayVars = this.pausedState?.vars ?? this.variables;
    const varCount = displayVars ? Object.keys(displayVars).length : 0;
    const isPaused = !!this.pausedState?.vars;
    
    const subtitle = isPaused 
      ? `Paused at ${this.pausedState?.location?.fileIdentifier || '?'}:${this.pausedState?.location?.lineNo || '?'}`
      : `Event index: ${this.selectedIndex}`;
    
    if (this.loading && !isPaused) {
      return html`
        <div class="panel-title">Variables</div>
        <div class="panel-subtitle">${subtitle}</div>
        <em>Loading...</em>
      `;
    }

    if (!displayVars || varCount === 0) {
      return html`
        <div class="panel-title">Variables</div>
        <div class="panel-subtitle">${subtitle} · No variables captured at this point</div>
        <em>Variables are captured when files are generated. Select an event after file generation starts.</em>
      `;
    }

    const rows = Object.entries(displayVars)
      .filter(([k]) => !k.startsWith('@'))
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([k, v]) => html`
        <tr>
          <td class="var-name">${escapeHtml(k)}</td>
          <td class="var-value" title="${escapeHtml(String(v))}">${escapeHtml(String(v))}</td>
        </tr>
      `);

    return html`
      <div class="panel-title">Variables</div>
      <div class="panel-subtitle">${subtitle} · ${varCount} variables</div>
      <table class="vars-table">
        <tr>
          <th>Variable</th>
          <th>Value</th>
        </tr>
        ${rows}
      </table>
    `;
  }
}

customElements.define('variables-panel', VariablesPanel);
