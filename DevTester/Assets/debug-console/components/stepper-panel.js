import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';

/**
 * stepper-panel
 *
 * Shown as a top bar in the debug console whenever the server sends a
 * `{ type: "paused", location, vars }` WebSocket message.
 *
 * Exposes one custom event:
 *   resume  → { detail: { mode: 'run' | 'stepOver' | 'stepInto' | 'stepOut' } }
 *
 * The parent (debug-app) forwards this to the WebSocket as a resume command.
 *
 * Properties:
 *   pausedState  — the full paused message from the server:
 *                  { location: { fileIdentifier, lineNo, lineContent }, vars }
 */
export class StepperPanel extends LitElement {
  static properties = {
    pausedState: { type: Object },
    isStepping: { type: Boolean }  // true while waiting for next pause
  };

  static styles = css`
    :host {
      display: block;
    }

    .bar {
      display: flex;
      align-items: center;
      gap: 0;
      background: #1c2833;
      border-bottom: 2px solid #c0392b;
      padding: 0 8px;
      min-height: 36px;
      font-size: 12px;
      color: #e8e8e8;
      flex-wrap: wrap;
      gap: 4px;
    }

    .paused-badge {
      background: #c0392b;
      color: #fff;
      border-radius: 3px;
      padding: 2px 8px;
      font-size: 11px;
      font-weight: 600;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      margin-right: 8px;
      flex-shrink: 0;
    }

    .location {
      color: #a0c4e8;
      font-family: 'SFMono-Regular', 'Consolas', monospace;
      font-size: 11px;
      flex: 1;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      min-width: 0;
    }

    .location .file {
      color: #9cdcfe;
    }

    .location .line {
      color: #b5cea8;
    }

    .location .content {
      color: #858585;
      margin-left: 6px;
    }

    .actions {
      display: flex;
      gap: 4px;
      margin-left: 8px;
      flex-shrink: 0;
    }

    .btn {
      display: flex;
      align-items: center;
      gap: 5px;
      background: #2c3e50;
      border: 1px solid #3d5166;
      color: #c8d8e8;
      border-radius: 4px;
      padding: 4px 10px;
      font-size: 11px;
      font-family: inherit;
      cursor: pointer;
      transition: background 0.12s, border-color 0.12s;
      white-space: nowrap;
    }

    .btn:hover {
      background: #34495e;
      border-color: #5d8aaa;
    }

    .btn.primary {
      background: #155724;
      border-color: #28a745;
      color: #a8e6b8;
    }

    .btn.primary:hover {
      background: #1e7e34;
    }

    .btn svg {
      width: 12px;
      height: 12px;
      flex-shrink: 0;
    }

    .vars-badge {
      font-size: 10px;
      color: #858585;
      margin-left: auto;
      padding-right: 4px;
      flex-shrink: 0;
    }

    /* Stepping indicator */
    .bar.stepping {
      opacity: 0.7;
      pointer-events: none;
    }

    .bar.stepping .paused-badge {
      background: #7f8c8d;
    }

    .stepping-indicator {
      display: inline-block;
      width: 10px;
      height: 10px;
      border: 2px solid #9cdcfe;
      border-top-color: transparent;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin-right: 6px;
    }

    @keyframes spin {
      to { transform: rotate(360deg); }
    }
  `;

  _resume(mode) {
    this.dispatchEvent(new CustomEvent('resume', {
      bubbles: true,
      composed: true,
      detail: { mode }
    }));
  }

  render() {
    const loc = this.pausedState?.location;
    const vars = this.pausedState?.vars ?? {};
    const varCount = Object.keys(vars).length;

    const fileName = loc?.fileIdentifier
      ? loc.fileIdentifier.split('/').pop()
      : '?';

    return html`
      <div class="bar ${this.isStepping ? 'stepping' : ''}">
        ${this.isStepping 
          ? html`<span class="stepping-indicator"></span><span class="paused-badge">Stepping...</span>`
          : html`<span class="paused-badge">Paused</span>`
        }

        <span class="location">
          <span class="file">${fileName}</span>
          ${loc?.lineNo != null
            ? html`<span class="line">:${loc.lineNo}</span>`
            : ''}
          ${loc?.lineContent
            ? html`<span class="content">${loc.lineContent.trim()}</span>`
            : ''}
        </span>

        <div class="actions">
          <!-- Continue / Run -->
          <button class="btn primary" title="Continue running (F5)" @click=${() => this._resume('run')}>
            <svg viewBox="0 0 16 16" fill="currentColor">
              <path d="M4 3.5l8 4.5-8 4.5V3.5z"/>
            </svg>
            Continue
          </button>

          <!-- Step Over -->
          <button class="btn" title="Step Over (F10)" @click=${() => this._resume('stepOver')}>
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4">
              <path d="M8 3v5m0 0l-3-3m3 3l3-3"/>
              <path d="M4 12h8" stroke-linecap="round"/>
            </svg>
            Step Over
          </button>

          <!-- Step Into -->
          <button class="btn" title="Step Into (F11)" @click=${() => this._resume('stepInto')}>
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4">
              <path d="M8 4v7m0 0l-3-3m3 3l3-3" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            Step Into
          </button>

          <!-- Step Out -->
          <button class="btn" title="Step Out (Shift+F11)" @click=${() => this._resume('stepOut')}>
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4">
              <path d="M8 12V5m0 0L5 8m3-3l3 3" stroke-linecap="round" stroke-linejoin="round"/>
              <path d="M4 3h8" stroke-linecap="round"/>
            </svg>
            Step Out
          </button>
        </div>

        ${varCount > 0
          ? html`<span class="vars-badge">${varCount} var${varCount !== 1 ? 's' : ''} in scope</span>`
          : ''}
      </div>
    `;
  }
}

customElements.define('stepper-panel', StepperPanel);
