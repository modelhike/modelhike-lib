import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { state } from '../utils/state.js';
import { loadSession } from '../utils/api.js';
import { buildFileWindows } from '../utils/file-tree-builder.js';
import './header-bar.js';
import './summary-bar.js';
import './file-tree-panel.js';
import './source-editor.js';
import './output-editor.js';
import './trace-panel.js';
import './variables-panel.js';
import './models-panel.js';
import './footer-bar.js';
import './pane-resizer.js';

export class DebugApp extends LitElement {
  static properties = {
    session: { type: Object, state: true },
    selectedIndex: { type: Number, state: true },
    currentWindow: { type: Object, state: true },
    visibleFileWindows: { type: Array, state: true },
    activeSidebarTab: { type: String, state: true }
  };

  static styles = css`
    :host {
      display: block;
      height: 100vh;
    }

    .layout {
      display: grid;
      grid-template-rows: auto auto 1fr auto;
      height: 100vh;
    }

    .main {
      display: grid;
      grid-template-columns: minmax(220px, var(--left-sidebar-width)) 6px minmax(0, 1fr) 6px minmax(240px, var(--right-sidebar-width));
      min-height: 0;
      overflow: hidden;
    }

    .editor-split {
      display: grid;
      grid-template-columns: minmax(0, 1fr);
      grid-template-rows: minmax(0, 1fr) minmax(0, 1fr);
      gap: 8px;
      height: 100%;
      min-height: 0;
      padding: 8px;
      overflow: hidden;
    }

    .editor-split > * {
      min-height: 0;
      overflow: hidden;
    }

    .sidebar {
      display: grid;
      grid-template-rows: auto 1fr;
      min-height: 0;
    }

    .sidebar-tabs {
      display: flex;
      border-bottom: 1px solid #333;
      background: #202123;
      position: sticky;
      top: 0;
      z-index: 2;
    }

    .sidebar-tab {
      flex: 1;
      background: transparent;
      border: 0;
      color: #a0a0a0;
      padding: 8px 6px;
      font: inherit;
      font-size: 11px;
      letter-spacing: .03em;
      text-transform: uppercase;
      cursor: pointer;
    }

    .sidebar-tab.active {
      background: #252526;
      color: #9cdcfe;
      border-bottom: 2px solid #4ec9b0;
    }

    .sidebar-view {
      display: none;
      height: 100%;
      overflow: auto;
    }

    .sidebar-view::-webkit-scrollbar {
      width: 8px;
    }

    .sidebar-view::-webkit-scrollbar-track {
      background: #1e1e1e;
    }

    .sidebar-view::-webkit-scrollbar-thumb {
      background: #424242;
      border-radius: 4px;
    }

    .sidebar-view::-webkit-scrollbar-thumb:hover {
      background: #555;
    }

    .sidebar-view.active {
      display: block;
    }

    .error-banner {
      background: #5a2020;
      padding: 10px;
      margin: 8px;
      border-radius: 4px;
    }

    .error-msg {
      color: #f48771;
    }
  `;

  constructor() {
    super();
    this.session = null;
    this.selectedIndex = 0;
    this.currentWindow = null;
    this.visibleFileWindows = [];
    this.activeSidebarTab = 'trace';
  }

  async connectedCallback() {
    super.connectedCallback();
    await this.loadSessionData();
  }

  async loadSessionData() {
    try {
      const session = await loadSession();
      state.session = session;
      state.fileWindows = buildFileWindows(session);
      state.fileTreeFilterIndex = state.selectedIndex;
      this.syncFromState();
    } catch (err) {
      console.error('Failed to load session:', err);
    }
  }

  syncFromState() {
    this.session = state.session;
    this.selectedIndex = state.selectedIndex;
    this.activeSidebarTab = state.activeSidebarTab;
    this.currentWindow = state.getCurrentFileWindow();
    this.visibleFileWindows = state.getVisibleFileWindows();
  }

  handleEventSelected(e) {
    state.setState({ selectedIndex: e.detail.index });
    this.syncFromState();
  }

  handleFileSelected(e) {
    state.setState({ 
      selectedIndex: e.detail.fileWindow.startIndex,
      activeSidebarTab: 'trace'
    });
    this.syncFromState();
  }

  handleTimelineChanged(e) {
    state.setState({ 
      selectedIndex: e.detail.index,
      fileTreeFilterIndex: e.detail.index
    });
    this.syncFromState();
  }

  handleTabClick(tab) {
    state.setState({ activeSidebarTab: tab });
    this.syncFromState();
  }

  render() {
    if (!this.session) {
      return html`<div style="padding: 20px; color: #858585;">Loading session data...</div>`;
    }

    return html`
      <div class="layout">
        <header-bar .phases=${this.session.phases || []}></header-bar>
        
        <summary-bar 
          .session=${this.session}
          .currentWindow=${this.currentWindow}
          .fileWindowsCount=${state.fileWindows.length}
        ></summary-bar>

        <div class="main">
          <file-tree-panel
            .session=${this.session}
            .visibleFileWindows=${this.visibleFileWindows}
            .currentWindow=${this.currentWindow}
            .totalFileWindows=${state.fileWindows.length}
            @file-selected=${this.handleFileSelected}
          ></file-tree-panel>

          <pane-resizer 
            cssVar="--left-sidebar-width" 
            mode="left"
          ></pane-resizer>

          <div class="editor-split">
            <source-editor
              .session=${this.session}
              .selectedIndex=${this.selectedIndex}
              .currentWindow=${this.currentWindow}
            ></source-editor>

            <output-editor
              .currentWindow=${this.currentWindow}
            ></output-editor>
          </div>

          <pane-resizer 
            cssVar="--right-sidebar-width" 
            mode="right"
          ></pane-resizer>

          <div class="sidebar">
            <div class="sidebar-tabs">
              <button 
                class="sidebar-tab ${this.activeSidebarTab === 'trace' ? 'active' : ''}"
                @click=${() => this.handleTabClick('trace')}
              >Trace</button>
              <button 
                class="sidebar-tab ${this.activeSidebarTab === 'variables' ? 'active' : ''}"
                @click=${() => this.handleTabClick('variables')}
              >Variables</button>
              <button 
                class="sidebar-tab ${this.activeSidebarTab === 'models' ? 'active' : ''}"
                @click=${() => this.handleTabClick('models')}
              >Models</button>
            </div>

            <trace-panel
              class="sidebar-view ${this.activeSidebarTab === 'trace' ? 'active' : ''}"
              .session=${this.session}
              .currentWindow=${this.currentWindow}
              .selectedIndex=${this.selectedIndex}
              @event-selected=${this.handleEventSelected}
            ></trace-panel>

            <variables-panel
              class="sidebar-view ${this.activeSidebarTab === 'variables' ? 'active' : ''}"
              .selectedIndex=${this.selectedIndex}
            ></variables-panel>

            <models-panel
              class="sidebar-view ${this.activeSidebarTab === 'models' ? 'active' : ''}"
              .session=${this.session}
            ></models-panel>
          </div>
        </div>

        ${this.session.errors && this.session.errors.length ? html`
          <div class="error-banner">
            <span class="error-msg">${this.session.errors.map(e => e.message).join('; ')}</span>
          </div>
        ` : ''}

        <footer-bar
          .session=${this.session}
          .selectedIndex=${this.selectedIndex}
          .currentWindow=${this.currentWindow}
          .fileWindowsCount=${state.fileWindows.length}
          @timeline-changed=${this.handleTimelineChanged}
        ></footer-bar>
      </div>
    `;
  }
}

customElements.define('debug-app', DebugApp);
