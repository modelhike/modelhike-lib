import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { escapeHtml, baseName } from '../utils/formatters.js';

export class SummaryBar extends LitElement {
  static properties = {
    session: { type: Object },
    currentWindow: { type: Object },
    fileWindowsCount: { type: Number }
  };

  static styles = css`
    :host {
      display: block;
      background: #202123;
      padding: 6px 10px;
      border-bottom: 1px solid #333;
    }

    .summary-content {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
    }

    .summary-pill {
      background: #2d2d2d;
      border: 1px solid #3c3c3c;
      border-radius: 999px;
      padding: 3px 8px;
      font-size: 10px;
      color: #c5c5c5;
    }
  `;

  render() {
    if (!this.session) return html``;

    const pills = [
      html`<span class="summary-pill">Events: ${this.session.events.length}</span>`,
      html`<span class="summary-pill">Generated files: ${this.session.files?.length || 0}</span>`,
      html`<span class="summary-pill">Phases: ${this.session.phases?.length || 0}</span>`
    ];

    if (this.currentWindow) {
      pills.push(html`<span class="summary-pill">Current file: ${escapeHtml(baseName(this.currentWindow.outputPath))}</span>`);
      pills.push(html`<span class="summary-pill">Window events: ${this.currentWindow.eventCount}</span>`);
    }

    return html`<div class="summary-content">${pills}</div>`;
  }
}

customElements.define('summary-bar', SummaryBar);
