import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';

export class HeaderBar extends LitElement {
  static properties = {
    phases: { type: Array },
    session: { type: Object }
  };

  static styles = css`
    :host {
      display: block;
      background: #252526;
      padding: 8px 12px;
      border-bottom: 1px solid #333;
    }

    .header-content {
      display: flex;
      align-items: center;
      gap: 12px;
    }

    h1 {
      margin: 0;
      font-size: 16px;
      color: #4ec9b0;
    }

    .summary {
      display: flex;
      gap: 8px;
      margin-left: auto;
      font-size: 11px;
      color: #858585;
    }

    .summary-item {
      display: flex;
      align-items: center;
      gap: 4px;
    }

    .summary-value {
      color: #c5c5c5;
    }

    .phases {
      display: flex;
      gap: 4px;
      flex-wrap: wrap;
    }

    .phase {
      padding: 4px 8px;
      background: #2d2d2d;
      border-radius: 4px;
      font-size: 11px;
    }

    .phase.done {
      background: #0e639c;
    }
  `;

  constructor() {
    super();
    this.phases = [];
  }

  render() {
    const eventCount = this.session?.events?.length || 0;
    const fileCount = this.session?.files?.length || 0;
    const phaseCount = this.session?.phases?.length || 0;

    return html`
      <div class="header-content">
        <h1>ModelHike Debug Console</h1>
        <div class="phases">
          ${this.phases.map(p => html`
            <span class="phase ${p.success ? 'done' : ''}">${p.name}</span>
          `)}
        </div>
        <div class="summary">
          <span class="summary-item">Events: <span class="summary-value">${eventCount}</span></span>
          <span class="summary-item">Files: <span class="summary-value">${fileCount}</span></span>
          <span class="summary-item">Phases: <span class="summary-value">${phaseCount}</span></span>
        </div>
      </div>
    `;
  }
}

customElements.define('header-bar', HeaderBar);
