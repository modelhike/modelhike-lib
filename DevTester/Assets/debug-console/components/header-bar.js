import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';

export class HeaderBar extends LitElement {
  static properties = {
    phases: { type: Array }
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
    return html`
      <div class="header-content">
        <h1>ModelHike Debug Console</h1>
        <div class="phases">
          ${this.phases.map(p => html`
            <span class="phase ${p.success ? 'done' : ''}">${p.name}</span>
          `)}
        </div>
      </div>
    `;
  }
}

customElements.define('header-bar', HeaderBar);
