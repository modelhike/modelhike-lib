import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { escapeHtml, baseName, eventType, eventLabel } from '../utils/formatters.js';

export class TracePanel extends LitElement {
  static properties = {
    session: { type: Object },
    currentWindow: { type: Object },
    selectedIndex: { type: Number }
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

    .current-file-card {
      background: #252526;
      border: 1px solid #333;
      border-radius: 4px;
      padding: 8px;
      margin-bottom: 8px;
    }

    .current-file-title {
      font-size: 12px;
      color: #dcdcaa;
    }

    .current-file-meta {
      font-size: 11px;
      color: #858585;
      margin-top: 4px;
      display: grid;
      gap: 3px;
    }

    .events-list {
      font-size: 12px;
    }

    .event-item {
      padding: 6px 8px;
      border-bottom: 1px solid #2d2d2d;
      cursor: pointer;
    }

    .event-item:hover {
      background: #2d2d2d;
    }

    .event-item.selected {
      background: #264f78;
    }

    .event-meta {
      display: flex;
      justify-content: space-between;
      gap: 8px;
      font-size: 11px;
      color: #858585;
    }

    .event-label {
      margin-top: 2px;
    }

    .event-badge {
      display: inline-block;
      padding: 2px 6px;
      border-radius: 999px;
      background: #333;
      color: #dcdcaa;
      font-size: 10px;
    }
  `;

  handleEventClick(index) {
    this.dispatchEvent(new CustomEvent('event-selected', {
      detail: { index },
      bubbles: true,
      composed: true
    }));
  }

  render() {
    if (!this.session) return html``;

    let displayEvents = this.session.events.map((event, index) => ({ event, index }));
    let metaText = 'Showing all events';

    if (this.currentWindow) {
      displayEvents = this.session.events
        .slice(this.currentWindow.startIndex, this.currentWindow.endIndex + 1)
        .map((event, offset) => ({ event, index: this.currentWindow.startIndex + offset }));
      metaText = `Events ${this.currentWindow.startIndex + 1}-${this.currentWindow.endIndex + 1} for ${baseName(this.currentWindow.outputPath)}`;
    }

    return html`
      <div class="panel-title">Current File Window</div>
      <div class="panel-subtitle">${metaText}</div>
      
      ${this.currentWindow ? html`
        <div class="current-file-card">
          <div class="current-file-title">${escapeHtml(this.currentWindow.outputPath)}</div>
          <div class="current-file-meta">
            <div>Object: ${escapeHtml(this.currentWindow.objectName || 'n/a')}</div>
            <div>Template: ${escapeHtml(this.currentWindow.templateName || 'n/a')}</div>
            <div>Working dir: ${escapeHtml(this.currentWindow.workingDir || '/')}</div>
            <div>Window: events ${this.currentWindow.startIndex + 1}-${this.currentWindow.endIndex + 1} (${this.currentWindow.eventCount} total)</div>
            <div>Control flow hits: ${this.currentWindow.controlFlowCount} | Templates entered: ${this.currentWindow.templateCount}</div>
          </div>
        </div>
      ` : ''}

      <div class="events-list">
        ${displayEvents.map(({ event, index }) => {
          const type = eventType(event);
          const isSelected = index === this.selectedIndex;
          return html`
            <div 
              class="event-item ${isSelected ? 'selected' : ''}" 
              @click=${() => this.handleEventClick(index)}
            >
              <div class="event-meta">
                <span>#${index + 1}</span>
                <span class="event-badge">${escapeHtml(type)}</span>
              </div>
              <div class="event-label">${escapeHtml(eventLabel(event))}</div>
            </div>
          `;
        })}
      </div>
    `;
  }
}

customElements.define('trace-panel', TracePanel);
