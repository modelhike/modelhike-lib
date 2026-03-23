import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { evaluateExpression } from '../utils/api.js';

export class FooterBar extends LitElement {
  static properties = {
    session: { type: Object },
    selectedIndex: { type: Number },
    currentWindow: { type: Object },
    fileWindowsCount: { type: Number },
    exprResult: { type: String, state: true }
  };

  static styles = css`
    :host {
      display: block;
      border-top: 1px solid #333;
      background: #1f1f1f;
    }

    .footer-content {
      display: grid;
      grid-template-rows: auto auto;
    }

    .footer-tools {
      display: flex;
      gap: 24px;
      flex-wrap: wrap;
      padding: 8px;
    }

    .panel-title {
      font-weight: 600;
      margin-bottom: 8px;
      color: #9cdcfe;
    }

    .playground {
      padding: 8px;
    }

    .playground input {
      width: 100%;
      padding: 8px;
      background: #3c3c3c;
      border: 1px solid #555;
      color: #d4d4d4;
      border-radius: 4px;
      margin-bottom: 8px;
      font-family: ui-monospace, monospace;
      font-size: 13px;
    }

    .playground pre {
      background: #2d2d2d;
      padding: 8px;
      overflow: auto;
      font-size: 12px;
      margin: 0;
    }

    .playground button {
      padding: 8px 16px;
      background: #3c3c3c;
      border: 1px solid #555;
      color: #d4d4d4;
      border-radius: 4px;
      cursor: pointer;
      font-family: inherit;
      font-size: 13px;
    }

    .playground button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .ws-status {
      color: #858585;
      font-size: 12px;
      margin-left: 8px;
    }

    .timeline {
      min-height: 22px;
      background: #252526;
      padding: 2px 8px;
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 11px;
      border-top: 1px solid #333;
    }

    .timeline-slider {
      flex: 1;
      height: 6px;
      background: #3c3c3c;
      border-radius: 4px;
      cursor: pointer;
    }
  `;

  constructor() {
    super();
    this.exprResult = 'Result will appear here';
  }

  async handleExpressionEval(e) {
    if (e.key === 'Enter') {
      const expr = e.target.value;
      try {
        const result = await evaluateExpression(expr, this.selectedIndex);
        this.exprResult = result.error || result.result || '';
      } catch (err) {
        this.exprResult = 'Error: ' + err.message;
      }
    }
  }

  handleTimelineChange(e) {
    const newIndex = parseInt(e.target.value);
    this.dispatchEvent(new CustomEvent('timeline-changed', {
      detail: { index: newIndex },
      bubbles: true,
      composed: true
    }));
  }

  render() {
    if (!this.session) return html``;

    const eventCount = this.session.events.length;
    const currentEventText = `${this.selectedIndex + 1} / ${eventCount}${this.currentWindow ? ' · file ' + (this.currentWindow.index + 1) + ' / ' + this.fileWindowsCount : ''}`;

    return html`
      <div class="footer-content">
        <div class="footer-tools">
          <div>
            <div class="panel-title">Live Stepping</div>
            <div class="playground" style="margin:0">
              <button disabled>Connect WebSocket</button>
              <span class="ws-status">(Post-mortem mode; live stepping requires --debug-stepping)</span>
            </div>
          </div>
          <div style="flex:1">
            <div class="panel-title">Expression Playground</div>
            <div class="playground">
              <input 
                type="text" 
                placeholder="e.g. {{ entity.name | lowercase }}"
                @keydown=${this.handleExpressionEval}
              >
              <pre>${this.exprResult}</pre>
            </div>
          </div>
        </div>
        <div class="timeline">
          <span>${eventCount} events across ${this.fileWindowsCount} files</span>
          <input 
            type="range" 
            class="timeline-slider"
            min="0" 
            max="${Math.max(0, eventCount - 1)}" 
            .value="${this.selectedIndex}"
            @input=${this.handleTimelineChange}
          >
          <span>${currentEventText}</span>
        </div>
      </div>
    `;
  }
}

customElements.define('footer-bar', FooterBar);
