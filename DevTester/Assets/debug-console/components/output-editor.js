import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { loadGeneratedFile } from '../utils/api.js';
import './code-panel.js';

export class OutputEditor extends LitElement {
  static properties = {
    currentWindow: { type: Object },
    outputContent: { type: String, state: true },
    outputPath: { type: String, state: true },
    loading: { type: Boolean, state: true },
    renderToken: { type: Number, state: true }
  };

  static styles = css`
    :host {
      display: grid;
      grid-template-rows: auto auto 1fr;
      min-height: 0;
      overflow: hidden;
    }

    .panel-title {
      font-weight: 600;
      margin-bottom: 8px;
      color: #9cdcfe;
      padding: 8px 8px 0;
    }

    .panel-meta {
      font-size: 11px;
      color: #858585;
      margin-bottom: 8px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      padding: 0 8px;
    }
  `;

  constructor() {
    super();
    this.outputContent = '';
    this.outputPath = 'Select a generated file';
    this.loading = false;
    this.renderToken = 0;
  }

  async updated(changedProperties) {
    if (changedProperties.has('currentWindow')) {
      await this.loadOutput();
    }
  }

  async loadOutput() {
    if (!this.currentWindow) {
      this.outputPath = 'No generated file selected';
      this.outputContent = '';
      return;
    }

    const token = ++this.renderToken;
    this.outputPath = this.currentWindow.outputPath;
    this.loading = true;

    try {
      const file = await loadGeneratedFile(this.currentWindow.index);
      if (token !== this.renderToken) return;
      this.outputContent = file.content;
      this.outputPath = file.resolvedPath || this.currentWindow.outputPath;
    } catch {
      if (token !== this.renderToken) return;
      this.outputContent = '';
      this.outputPath = this.currentWindow.outputPath;
    } finally {
      if (token === this.renderToken) {
        this.loading = false;
      }
    }
  }

  render() {
    return html`
      <div class="panel-title">Generated Output</div>
      <div class="panel-meta">${this.outputPath}</div>
      <code-panel 
        .content=${this.outputContent}
        emptyMessage="Generated file not found on disk"
      ></code-panel>
    `;
  }
}

customElements.define('output-editor', OutputEditor);
