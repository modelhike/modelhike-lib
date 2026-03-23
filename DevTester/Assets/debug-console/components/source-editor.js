import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { loadSourceFile } from '../utils/api.js';
import { getSourceLocation, hasValidSourceLocation } from '../utils/formatters.js';
import './code-panel.js';

export class SourceEditor extends LitElement {
  static properties = {
    session: { type: Object },
    selectedIndex: { type: Number },
    currentWindow: { type: Object },
    sourceContent: { type: String, state: true },
    sourceIdentifier: { type: String, state: true },
    highlightLine: { type: Number, state: true },
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
    this.sourceContent = '';
    this.sourceIdentifier = '';
    this.highlightLine = 0;
    this.loading = false;
    this.renderToken = 0;
  }

  getDisplaySourceLocation() {
    if (!this.session) return null;
    const selectedEvent = this.session.events[this.selectedIndex];
    const selectedLocation = selectedEvent ? getSourceLocation(selectedEvent) : null;
    if (hasValidSourceLocation(selectedLocation)) return selectedLocation;
    
    if (this.currentWindow) {
      for (let index = this.currentWindow.startIndex; index <= this.currentWindow.endIndex; index++) {
        const candidate = getSourceLocation(this.session.events[index]);
        if (hasValidSourceLocation(candidate)) return candidate;
      }
    }
    return null;
  }

  sourceIdentifierForWindow(loc) {
    if (this.currentWindow && this.currentWindow.templateName) return this.currentWindow.templateName;
    return loc && loc.fileIdentifier ? loc.fileIdentifier : '';
  }

  async updated(changedProperties) {
    if (changedProperties.has('selectedIndex') || changedProperties.has('currentWindow') || changedProperties.has('session')) {
      await this.loadSource();
    }
  }

  async loadSource() {
    if (!this.session) return;

    const loc = this.getDisplaySourceLocation();
    const identifier = this.sourceIdentifierForWindow(loc);

    if (!identifier) {
      this.sourceIdentifier = 'No source for this selection';
      this.sourceContent = '';
      this.highlightLine = 0;
      return;
    }

    const token = ++this.renderToken;
    this.sourceIdentifier = identifier + (loc && loc.lineNo > 0 ? ' · line ' + loc.lineNo : '');
    this.loading = true;

    try {
      const file = await loadSourceFile(identifier);
      if (token !== this.renderToken) return;
      this.sourceContent = file.content;
      this.highlightLine = loc && loc.fileIdentifier === file.identifier ? loc.lineNo : 0;
      this.sourceIdentifier = file.identifier + (this.highlightLine > 0 ? ' · line ' + this.highlightLine : '');
    } catch {
      if (token !== this.renderToken) return;
      this.sourceIdentifier = identifier + ' · missing';
      this.sourceContent = '';
      this.highlightLine = 0;
    } finally {
      if (token === this.renderToken) {
        this.loading = false;
      }
    }
  }

  render() {
    return html`
      <div class="panel-title">Template Source</div>
      <div class="panel-meta">${this.sourceIdentifier || 'Select an event'}</div>
      <code-panel 
        .content=${this.sourceContent} 
        .highlightLine=${this.highlightLine}
        emptyMessage="No source for this event"
      ></code-panel>
    `;
  }
}

customElements.define('source-editor', SourceEditor);
