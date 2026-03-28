import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { state } from '../utils/state.js';
import { loadSession, loadMode, connectWebSocket } from '../utils/api.js';
import { buildFileWindows } from '../utils/file-tree-builder.js';
import { DebugConsole } from '../utils/debug-console.js';
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
import './stepper-panel.js';
import './problems-panel.js';

export class DebugApp extends LitElement {
  static properties = {
    session: { type: Object, state: true },
    selectedIndex: { type: Number, state: true },
    currentWindow: { type: Object, state: true },
    visibleFileWindows: { type: Array, state: true },
    activeSidebarTab: { type: String, state: true },
    serverMode: { type: String, state: true },
    pausedState: { type: Object, state: true },   // { location, vars } or null
    liveRunning: { type: Boolean, state: true },   // true while pipeline is running
    isStepping: { type: Boolean, state: true },   // true while waiting for next step
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

    .sidebar-view::-webkit-scrollbar { width: 8px; }
    .sidebar-view::-webkit-scrollbar-track { background: #1e1e1e; }
    .sidebar-view::-webkit-scrollbar-thumb { background: #424242; border-radius: 4px; }
    .sidebar-view::-webkit-scrollbar-thumb:hover { background: #555; }

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

    .live-banner {
      display: flex;
      align-items: center;
      gap: 8px;
      background: #1a2c1a;
      border-bottom: 1px solid #2a4a2a;
      padding: 6px 12px;
      font-size: 12px;
      color: #7ec87e;
    }

    .live-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #4ec94e;
      animation: pulse 1.2s ease-in-out infinite;
      flex-shrink: 0;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.3; }
    }
  `;

  constructor() {
    super();
    this.session = null;
    this.selectedIndex = 0;
    this.currentWindow = null;
    this.visibleFileWindows = [];
    this.activeSidebarTab = 'trace';
    this.serverMode = 'postMortem';
    this.pausedState = null;
    this.liveRunning = false;
    this._ws = null;
  }

  async connectedCallback() {
    super.connectedCallback();
    await this.loadSessionData();
    this._keydownHandler = (e) => this._handleKeydown(e);
    window.addEventListener('keydown', this._keydownHandler);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._ws?.close();
    if (this._keydownHandler) window.removeEventListener('keydown', this._keydownHandler);
  }

  async _refreshProblemsPanel() {
    await this.updateComplete;
    const panel = this.shadowRoot?.getElementById('problemsPanel');
    if (panel && typeof panel.loadDiagnostics === 'function') {
      panel.loadDiagnostics();
    }
  }

  _handleKeydown(e) {
    const inInput = e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT');
    if (inInput) return;

    if (this.serverMode !== 'stepping') return;

    // F5 = continue / resume
    if (e.key === 'F5' && !e.shiftKey) {
      e.preventDefault();
      if (this.pausedState) this._sendResume('continue');
    }
    // F10 = step over
    if (e.key === 'F10') {
      e.preventDefault();
      if (this.pausedState) this._sendResume('stepOver');
    }
    // F11 = step into
    if (e.key === 'F11' && !e.shiftKey) {
      e.preventDefault();
      if (this.pausedState) this._sendResume('stepInto');
    }
    // Shift+F11 = step out
    if (e.key === 'F11' && e.shiftKey) {
      e.preventDefault();
      if (this.pausedState) this._sendResume('stepOut');
    }
    // Tab switching: Ctrl+1/2/3/4
    if (e.ctrlKey && e.key === '1') { e.preventDefault(); this.handleTabClick('trace'); }
    if (e.ctrlKey && e.key === '2') { e.preventDefault(); this.handleTabClick('variables'); }
    if (e.ctrlKey && e.key === '3') { e.preventDefault(); this.handleTabClick('models'); }
    if (e.ctrlKey && e.key === '4') { e.preventDefault(); this.handleTabClick('problems'); }
  }

  _sendResume(mode) {
    if (this._ws && this._ws.readyState === WebSocket.OPEN) {
      this._ws.send(JSON.stringify({ type: 'resume', mode }));
      this.isStepping = true;
    }
  }

  async loadSessionData() {
    try {
      // Check the server mode first
      const mode = await loadMode();
      this.serverMode = mode;

      if (mode === 'stepping') {
        // In stepping mode: load initial (possibly empty) session, then
        // open a WebSocket and stream events as the pipeline runs.
        const session = await loadSession();
        state.session = session;
        state.fileWindows = buildFileWindows(session);
        this.syncFromState();
        this.liveRunning = true;
        this._connectLiveWS();
      } else {
        // Post-mortem: load the full completed session once.
        const session = await loadSession();
        state.session = session;
        state.fileWindows = buildFileWindows(session);
        state.fileTreeFilterIndex = state.selectedIndex;
        this.syncFromState();
        await this._refreshProblemsPanel();
      }
    } catch (err) {
      DebugConsole.error('Failed to load session:', err);
      // Show a helpful error state instead of a blank screen
      state.session = {
        events: [],
        phases: [],
        errors: [{ message: `Failed to connect to debug server: ${err.message || err}. Is it running on the correct port?` }],
        config: {},
      };
      state.fileWindows = [];
      this.syncFromState();
      // Retry in 3s in case the server isn't ready yet
      setTimeout(() => this.loadSessionData(), 3000);
    }
  }

  async _connectLiveWS() {
    // Store pause state from REST to show after WebSocket connects
    let initialPauseState = null;
    try {
      const pauseResp = await fetch('/api/pause-state');
      const pauseData = await pauseResp.json();
      if (pauseData && pauseData.type === 'paused') {
        DebugConsole.log('Server already paused (from REST)');
        initialPauseState = pauseData;
      }
    } catch (e) {
      DebugConsole.warn('Could not check pause state:', e);
    }

    this._ws = connectWebSocket({
      onEvent: (envelope) => {
        // Append event to the live session and refresh UI
        if (state.session) {
          const newEvents = [...(state.session.events || []), envelope];
          state.session = {
            ...state.session,
            events: newEvents
          };
          state.fileWindows = buildFileWindows(state.session);
          
          // Auto-track: move timeline to latest event during live streaming
          if (this.liveRunning) {
            state.selectedIndex = newEvents.length - 1;
            state.fileTreeFilterIndex = newEvents.length - 1;
          }
          
          this.syncFromState();
        }
      },
      onPaused: (msg) => {
        DebugConsole.log('Received PAUSED message:', msg);
        this.pausedState = msg;
        this.liveRunning = false;
        this.isStepping = false;
        
        // Update file tree to show all files generated so far
        if (state.session && state.session.events) {
          state.fileTreeFilterIndex = state.session.events.length - 1;
          this.visibleFileWindows = state.getVisibleFileWindows();
        }
        
        this.requestUpdate();
      },
      onCompleted: async () => {
        this.liveRunning = false;
        this.pausedState = null;
        // Reload the full session now that the pipeline has finished
        try {
          const session = await loadSession();
          state.session = session;
          state.fileWindows = buildFileWindows(session);
          this.syncFromState();
          await this._refreshProblemsPanel();
        } catch (err) {
          DebugConsole.error('Failed to reload completed session:', err);
        }
      },
      onOpen: () => {
        DebugConsole.log('WebSocket live session connected');
        if (initialPauseState) {
          DebugConsole.log('Showing initial pause state now that WS is connected');
          this.pausedState = initialPauseState;
          this.liveRunning = false;
          this.requestUpdate();
        }
      },
      onClose: () => {
        this.liveRunning = false;
      }
    });
  }

  get _problemCount() {
    const events = this.session?.events || [];
    return events.filter(ev => {
      const t = Object.keys(ev.event || {})[0];
      return t === 'error' || (t === 'diagnostic' && (ev.event?.diagnostic?.severity === 'error' || ev.event?.diagnostic?.severity === 'warning'));
    }).length;
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

  handleProblemSelected(e) {
    const { eventIndex } = e.detail || {};
    if (eventIndex == null) return;
    state.setState({
      selectedIndex: eventIndex,
      fileTreeFilterIndex: eventIndex,
      activeSidebarTab: 'trace',
    });
    this.syncFromState();
  }

  handleStepperResume(e) {
    const { mode } = e.detail;
    this._sendResume(mode);
    if (mode === 'run' || mode === 'continue') {
      this.pausedState = null;
      this.liveRunning = true;
      this.requestUpdate();
    } else {
      this.isStepping = true;
      this.requestUpdate();
    }
  }

  render() {
    if (!this.session) {
      return html`
        <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;gap:12px;color:#858585;font-family:monospace;">
          <div style="font-size:32px">⏳</div>
          <div style="font-size:14px">Connecting to debug server…</div>
          <div style="font-size:11px;color:#555">Ensure DevTester is running with --debug or --debug-stepping</div>
        </div>
      `;
    }

    return html`
      <div class="layout">
        <header-bar .phases=${this.session.phases || []} .session=${this.session}></header-bar>

        ${this.serverMode === 'stepping' && this.liveRunning
          ? html`<div class="live-banner"><span class="live-dot"></span> Pipeline running — streaming events live…</div>`
          : ''
        }

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
              .pausedState=${this.pausedState}
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
              <button 
                class="sidebar-tab ${this.activeSidebarTab === 'problems' ? 'active' : ''}"
                @click=${() => this.handleTabClick('problems')}
              >Problems${this._problemCount > 0 ? html` <span style="background:#f48771;color:#1e1e1e;border-radius:8px;padding:0 5px;font-size:10px;font-weight:700;margin-left:3px">${this._problemCount}</span>` : ''}</button>
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
              .pausedState=${this.pausedState}
            ></variables-panel>

            <models-panel
              class="sidebar-view ${this.activeSidebarTab === 'models' ? 'active' : ''}"
              .session=${this.session}
            ></models-panel>

            <problems-panel
              id="problemsPanel"
              class="sidebar-view ${this.activeSidebarTab === 'problems' ? 'active' : ''}"
              .events=${this.session?.events || []}
              @problem-selected=${this.handleProblemSelected}
            ></problems-panel>
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

        ${this.serverMode === 'stepping' && this.pausedState
          ? html`<stepper-panel
              .pausedState=${this.pausedState}
              .isStepping=${this.isStepping}
              @resume=${this.handleStepperResume}
            ></stepper-panel>
            <div style="padding:4px 10px;background:#1a1a2a;border-top:1px solid #333;font-size:10px;color:#555;display:flex;gap:16px;">
              <span><kbd>F5</kbd> Continue</span>
              <span><kbd>F10</kbd> Step Over</span>
              <span><kbd>F11</kbd> Step Into</span>
              <span><kbd>⇧F11</kbd> Step Out</span>
              <span><kbd>Ctrl+1-4</kbd> Switch tab</span>
            </div>`
          : ''
        }
      </div>
    `;
  }
}

customElements.define('debug-app', DebugApp);
