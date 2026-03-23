import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { escapeHtml } from '../utils/formatters.js';

export class CodePanel extends LitElement {
  static properties = {
    content: { type: String },
    highlightLine: { type: Number },
    emptyMessage: { type: String }
  };

  constructor() {
    super();
    this._lastScrolledLine = 0;
  }

  updated(changedProperties) {
    if (changedProperties.has('highlightLine') && this.highlightLine > 0) {
      // Only scroll if the line changed (not just a re-render)
      if (this.highlightLine !== this._lastScrolledLine) {
        this._lastScrolledLine = this.highlightLine;
        this._scrollToHighlight();
      }
    }
  }

  _scrollToHighlight() {
    // Use requestAnimationFrame to ensure DOM is updated
    requestAnimationFrame(() => {
      const highlighted = this.renderRoot.querySelector('.source-line.highlight');
      if (highlighted) {
        highlighted.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    });
  }

  static styles = css`
    :host {
      display: block;
      font-family: ui-monospace, monospace;
      overflow: auto;
      border: 1px solid #333;
      background: #1e1e1e;
      min-height: 0;
    }

    :host::-webkit-scrollbar {
      width: 8px;
      height: 8px;
    }

    :host::-webkit-scrollbar-track {
      background: #1e1e1e;
    }

    :host::-webkit-scrollbar-thumb {
      background: #424242;
      border-radius: 4px;
    }

    :host::-webkit-scrollbar-thumb:hover {
      background: #555;
    }

    .source-line {
      display: flex;
      line-height: 1.5;
      padding: 0 4px;
    }

    .source-line:hover {
      background: #2d2d2d;
    }

    .source-line.highlight {
      background: #3a3a00;
    }

    .gutter {
      width: 3em;
      text-align: right;
      padding-right: 8px;
      color: #858585;
      user-select: none;
    }

    .source-code {
      flex: 1;
      white-space: pre-wrap;
      word-break: break-all;
    }

    em {
      color: #858585;
      padding: 8px;
      display: block;
    }
  `;

  render() {
    if (!this.content) {
      return html`<em>${this.emptyMessage || 'No content'}</em>`;
    }

    const lines = String(this.content).split('\n');
    return html`
      ${lines.map((line, i) => {
        const lineNum = i + 1;
        const isHighlight = this.highlightLine && lineNum === this.highlightLine;
        return html`
          <div class="source-line ${isHighlight ? 'highlight' : ''}">
            <span class="gutter">${lineNum}</span>
            <code class="source-code">${escapeHtml(line)}</code>
          </div>
        `;
      })}
    `;
  }
}

customElements.define('code-panel', CodePanel);
