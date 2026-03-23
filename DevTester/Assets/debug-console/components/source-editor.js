import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { loadSourceFile } from '../utils/api.js';
import { getSourceLocation, hasValidSourceLocation } from '../utils/formatters.js';
import './code-panel.js';

export class SourceEditor extends LitElement {
  static properties = {
    session: { type: Object },
    selectedIndex: { type: Number },
    currentWindow: { type: Object },
    pausedState: { type: Object },  // stepping mode: { location: { fileIdentifier, lineNo, lineContent } }
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
    // Priority 1: Show paused stepping location
    if (this.pausedState && this.pausedState.location) {
      return this.pausedState.location;
    }
    
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
    // For paused state, use the location's fileIdentifier directly
    if (this.pausedState && this.pausedState.location) {
      return this.pausedState.location.fileIdentifier;
    }
    if (this.currentWindow && this.currentWindow.templateName) return this.currentWindow.templateName;
    return loc && loc.fileIdentifier ? loc.fileIdentifier : '';
  }

  async updated(changedProperties) {
    if (changedProperties.has('selectedIndex') || changedProperties.has('currentWindow') || changedProperties.has('session') || changedProperties.has('pausedState')) {
      await this.loadSource();
    }
  }

  async loadSource() {
    // In stepping mode with paused state, we don't need a session
    if (!this.session && !this.pausedState) return;

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
      // Match by checking if identifiers are the same or one ends with the other
      const locId = loc?.fileIdentifier || '';
      const fileId = file.identifier || '';
      const identifiersMatch = locId === fileId || 
        locId.endsWith('/' + fileId) || fileId.endsWith('/' + locId) ||
        locId.endsWith(fileId) || fileId.endsWith(locId);
      this.highlightLine = loc && identifiersMatch ? loc.lineNo : 0;
      this.sourceIdentifier = file.identifier + (this.highlightLine > 0 ? ' · line ' + this.highlightLine : '');
    } catch (err) {
      if (token !== this.renderToken) return;
      console.warn('[source-editor] Failed to load source:', identifier, err);
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
