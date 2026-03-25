import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { escapeHtml, baseName, eventType, eventLabel, eventCssClass } from '../utils/formatters.js';

// Fixed row height (px). Must match .event-item height below.
const ITEM_H = 40;
// Extra rows rendered above and below the visible viewport.
const BUFFER = 25;

export class TracePanel extends LitElement {
  static properties = {
    session:         { type: Object },
    currentWindow:   { type: Object },
    selectedIndex:   { type: Number },
    _searchQuery:    { type: String,  state: true },
    _severityFilter: { type: String,  state: true },
    _scrollTop:      { type: Number,  state: true },
    _containerH:     { type: Number,  state: true },
  };

  static styles = css`
    :host {
      display: block;
      height: 100%;
      overflow: hidden;
    }

    .root {
      display: flex;
      flex-direction: column;
      height: 100%;
      overflow: hidden;
    }

    .header-section {
      flex-shrink: 0;
      padding: 8px 8px 4px;
      background: var(--bg-panel-alt, #202123);
      border-bottom: 1px solid var(--border, #333);
    }

    .scroll-container {
      flex: 1;
      overflow-y: auto;
      overflow-x: hidden;
      position: relative;
    }

    .scroll-container::-webkit-scrollbar        { width: 6px; }
    .scroll-container::-webkit-scrollbar-track  { background: var(--bg-app, #1e1e1e); }
    .scroll-container::-webkit-scrollbar-thumb  { background: #424242; border-radius: 3px; }
    .scroll-container::-webkit-scrollbar-thumb:hover { background: #666; }

    .panel-title {
      font-weight: 600;
      margin-bottom: 4px;
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 0.07em;
      color: var(--text-accent, #9cdcfe);
    }

    .panel-subtitle {
      font-size: 11px;
      color: var(--text-dim, #858585);
      margin-bottom: 6px;
    }

    .current-file-card {
      background: var(--bg-panel, #252526);
      border: 1px solid var(--border, #333);
      border-left: 3px solid var(--text-teal, #4ec9b0);
      border-radius: var(--radius, 4px);
      padding: 7px 8px;
      margin-bottom: 6px;
    }

    .current-file-title {
      font-size: 12px;
      color: var(--text-keyword, #dcdcaa);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .current-file-meta {
      font-size: 10px;
      color: var(--text-dim, #858585);
      margin-top: 3px;
      display: grid;
      gap: 2px;
    }

    .search-bar {
      display: flex;
      gap: 4px;
    }

    .search-bar input {
      flex: 1;
      background: var(--bg-input, #3c3c3c);
      border: 1px solid var(--border, #333);
      border-radius: var(--radius, 4px);
      color: var(--text, #d4d4d4);
      font-size: 11px;
      padding: 3px 7px;
      outline: none;
      font-family: inherit;
      transition: border-color 0.1s;
    }
    .search-bar input:focus { border-color: var(--text-teal, #4ec9b0); }

    .search-bar select {
      background: var(--bg-input, #3c3c3c);
      border: 1px solid var(--border, #333);
      border-radius: var(--radius, 4px);
      color: var(--text, #d4d4d4);
      font-size: 11px;
      padding: 3px 4px;
      outline: none;
      font-family: inherit;
    }

    .no-results {
      padding: 24px;
      text-align: center;
      color: var(--text-dim, #6a6a6a);
      font-size: 11px;
    }

    /* ---- Virtual scroll ---- */

    /* Outer container: sized to hold all items so the scrollbar is correct. */
    .virtual-list {
      position: relative;
    }

    /* Each event row: absolutely positioned at its computed offset. */
    .event-item {
      position: absolute;
      left: 0;
      right: 0;
      height: 40px;  /* must match ITEM_H constant above */
      box-sizing: border-box;
      padding: 0 8px;
      border-bottom: 1px solid var(--border-subtle, #2d2d2d);
      cursor: pointer;
      display: flex;
      flex-direction: column;
      justify-content: center;
      gap: 1px;
      transition: background 0.07s;
    }

    .event-item:hover   { background: var(--bg-hover, #2a2d2e); }
    .event-item.selected { background: var(--bg-selected, #264f78) !important; }

    .event-meta {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 8px;
      font-size: 10px;
      color: var(--text-dim, #858585);
      line-height: 1.2;
    }

    .event-label {
      font-size: 11px;
      color: var(--text, #d4d4d4);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      line-height: 1.3;
    }

    .event-badge {
      display: inline-block;
      padding: 1px 5px;
      border-radius: var(--radius-pill, 999px);
      background: var(--bg-badge, #2d2d2d);
      color: var(--text-keyword, #dcdcaa);
      font-size: 9px;
      flex-shrink: 0;
      letter-spacing: 0.03em;
    }

    /* ---- Severity / type row tints ---- */
    .trace-error               { border-left: 3px solid var(--clr-error, #f48771); }
    .trace-diagnostic          { }
    .trace-diagnostic--error   { border-left: 3px solid var(--clr-error, #f48771);   background: var(--bg-error,   rgba(244,135,113,.07)); }
    .trace-diagnostic--warning { border-left: 3px solid var(--clr-warning, #cca700); background: var(--bg-warning, rgba(204,167,0,.07)); }
    .trace-diagnostic--info    { border-left: 3px solid var(--clr-info, #4fc1ff);    background: var(--bg-info,    rgba(79,193,255,.07)); }
    .trace-phase               { background: var(--ev-phase-bg, #1b261b); }
    .trace-file                { background: var(--ev-file-bg,  #191929); }
    .trace-log                 { background: var(--ev-log-bg,   #1a1a28); }
    .trace-script,
    .trace-template            { background: var(--bg-row-alt,  #222); }
  `;

  constructor() {
    super();
    this._searchQuery    = '';
    this._severityFilter = 'all';
    this._scrollTop      = 0;
    this._containerH     = 600;
    this._ro             = null;
  }

  connectedCallback() {
    super.connectedCallback();
    this.updateComplete.then(() => this._initObserver());
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._ro?.disconnect();
    this._ro = null;
  }

  _initObserver() {
    const el = this.shadowRoot?.querySelector('.scroll-container');
    if (!el || this._ro) return;
    this._ro = new ResizeObserver(() => {
      this._containerH = el.clientHeight || 600;
    });
    this._ro.observe(el);
    this._containerH = el.clientHeight || 600;
  }

  _onScrolled(e) {
    this._scrollTop = e.target.scrollTop;
  }

  updated(changedProperties) {
    if (!this._ro) this._initObserver();
    if (changedProperties.has('selectedIndex') || changedProperties.has('currentWindow')) {
      this._scrollToSelected();
    }
  }

  // Compute filtered/windowed events (shared by render + scrollToSelected).
  _computeDisplayEvents() {
    if (!this.session) return [];
    let allEvents = this.session.events.map((event, index) => ({ event, index }));
    if (this.currentWindow) {
      allEvents = this.session.events
        .slice(this.currentWindow.startIndex, this.currentWindow.endIndex + 1)
        .map((event, offset) => ({ event, index: this.currentWindow.startIndex + offset }));
    }
    return allEvents.filter(({ event }) => this._matchesFilter(event));
  }

  _scrollToSelected() {
    const el = this.shadowRoot?.querySelector('.scroll-container');
    if (!el || this.selectedIndex == null) return;
    const pos = this._computeDisplayEvents().findIndex(({ index }) => index === this.selectedIndex);
    if (pos < 0) return;
    const itemTop = pos * ITEM_H;
    const alreadyVisible = itemTop >= this._scrollTop && itemTop + ITEM_H <= this._scrollTop + this._containerH;
    if (!alreadyVisible) {
      el.scrollTo({ top: Math.max(0, itemTop - this._containerH / 2 + ITEM_H / 2), behavior: 'smooth' });
    }
  }

  handleEventClick(index) {
    this.dispatchEvent(new CustomEvent('event-selected', {
      detail: { index },
      bubbles: true,
      composed: true,
    }));
  }

  _matchesFilter(event) {
    const q  = (this._searchQuery    || '').toLowerCase().trim();
    const sf = (this._severityFilter || 'all');

    if (sf !== 'all') {
      const t = eventType(event);
      if (sf === 'errors'  && t !== 'error'       && t !== 'diagnostic')  return false;
      if (sf === 'files'   && t !== 'fileGenerated'&& t !== 'fileCopied' && t !== 'fileSkipped') return false;
      if (sf === 'phases'  && t !== 'phaseStarted' && t !== 'phaseCompleted' && t !== 'phaseFailed') return false;
      if (sf === 'scripts' && t !== 'scriptStarted'&& t !== 'scriptCompleted'
                           && t !== 'templateStarted' && t !== 'templateCompleted') return false;
    }

    if (!q) return true;
    return eventLabel(event).toLowerCase().includes(q) || eventType(event).toLowerCase().includes(q);
  }

  _resetScroll() {
    this._scrollTop = 0;
    this.shadowRoot?.querySelector('.scroll-container')?.scrollTo(0, 0);
  }

  render() {
    if (!this.session) return html``;

    const displayEvents = this._computeDisplayEvents();
    const totalItems    = displayEvents.length;

    // Virtual scroll window
    const startIdx = Math.max(0, Math.floor(this._scrollTop / ITEM_H) - BUFFER);
    const endIdx   = Math.min(totalItems - 1, Math.ceil((this._scrollTop + this._containerH) / ITEM_H) + BUFFER);
    const visible  = displayEvents.slice(startIdx, endIdx + 1);
    const totalH   = totalItems * ITEM_H;

    const metaText = this.currentWindow
      ? `${totalItems} events  ·  ${baseName(this.currentWindow.outputPath)}`
      : `${totalItems.toLocaleString()} event${totalItems !== 1 ? 's' : ''}`;

    return html`
      <div class="root">

        <div class="header-section">
          <div class="panel-title">Event Trace</div>
          <div class="panel-subtitle">${metaText}</div>

          ${this.currentWindow ? html`
            <div class="current-file-card">
              <div class="current-file-title">${escapeHtml(this.currentWindow.outputPath)}</div>
              <div class="current-file-meta">
                <div>Object: ${escapeHtml(this.currentWindow.objectName || 'n/a')}
                  &nbsp;·&nbsp; Template: ${escapeHtml(this.currentWindow.templateName || 'n/a')}</div>
                <div>Working dir: ${escapeHtml(this.currentWindow.workingDir || '/')}</div>
                <div>${this.currentWindow.eventCount} events
                  &nbsp;·&nbsp; ${this.currentWindow.controlFlowCount} control flow
                  &nbsp;·&nbsp; ${this.currentWindow.templateCount} templates</div>
              </div>
            </div>
          ` : ''}

          <div class="search-bar">
            <input
              type="search"
              placeholder="Search events…"
              .value="${this._searchQuery}"
              @input="${e => { this._searchQuery = e.target.value; this._resetScroll(); }}"
            />
            <select
              .value="${this._severityFilter}"
              @change="${e => { this._severityFilter = e.target.value; this._resetScroll(); }}"
            >
              <option value="all">All</option>
              <option value="errors">Errors</option>
              <option value="files">Files</option>
              <option value="phases">Phases</option>
              <option value="scripts">Scripts</option>
            </select>
          </div>
        </div>

        <div class="scroll-container" @scroll="${this._onScrolled}">
          ${totalItems === 0
            ? html`<div class="no-results">No events match the current filter.</div>`
            : html`
              <div class="virtual-list" style="height: ${totalH}px">
                ${visible.map(({ event, index }, i) => html`
                  <div
                    class="event-item ${index === this.selectedIndex ? 'selected' : ''} ${eventCssClass(event)}"
                    style="top: ${(startIdx + i) * ITEM_H}px"
                    @click=${() => this.handleEventClick(index)}
                  >
                    <div class="event-meta">
                      <span>#${index + 1}</span>
                      <span class="event-badge">${escapeHtml(eventType(event))}</span>
                    </div>
                    <div class="event-label">${escapeHtml(eventLabel(event))}</div>
                  </div>
                `)}
              </div>
            `
          }
        </div>

      </div>
    `;
  }
}

customElements.define('trace-panel', TracePanel);
