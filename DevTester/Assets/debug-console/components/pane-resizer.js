import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';

export class PaneResizer extends LitElement {
  static properties = {
    cssVar: { type: String },
    mode: { type: String },
    isDragging: { type: Boolean, state: true }
  };

  static styles = css`
    :host {
      display: flex;
      align-items: center;
      justify-content: center;
      background: #252526;
      border-left: 1px solid #333;
      border-right: 1px solid #333;
      cursor: col-resize;
      position: relative;
      width: 6px;
      min-width: 6px;
    }

    :host(:hover),
    :host(.dragging) {
      background: #3f4345;
    }

    .handle {
      width: 2px;
      height: 36px;
      background: #4ec9b0;
      border-radius: 999px;
      opacity: 0.5;
      pointer-events: none;
    }

    :host(:hover) .handle,
    :host(.dragging) .handle {
      opacity: 1;
    }
  `;

  constructor() {
    super();
    this.cssVar = '--sidebar-width';
    this.mode = 'left';
    this.isDragging = false;
  }

  connectedCallback() {
    super.connectedCallback();
    this.boundOnPointerMove = this.onPointerMove.bind(this);
    this.boundStopDragging = this.stopDragging.bind(this);
    this.addEventListener('pointerdown', this.onPointerDown.bind(this));
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this.stopDragging();
  }

  onPointerDown(e) {
    this.isDragging = true;
    this.classList.add('dragging');
    document.body.style.userSelect = 'none';
    document.body.style.cursor = 'col-resize';
    window.addEventListener('pointermove', this.boundOnPointerMove);
    window.addEventListener('pointerup', this.boundStopDragging);
    e.preventDefault();
  }

  onPointerMove(e) {
    if (!this.isDragging) return;
    const minWidth = 220;
    const maxWidth = Math.min(700, Math.floor(window.innerWidth * 0.45));
    const nextWidth = this.mode === 'left'
      ? Math.max(minWidth, Math.min(maxWidth, e.clientX))
      : Math.max(minWidth, Math.min(maxWidth, window.innerWidth - e.clientX));
    document.documentElement.style.setProperty(this.cssVar, nextWidth + 'px');
  }

  stopDragging() {
    if (!this.isDragging) return;
    this.isDragging = false;
    this.classList.remove('dragging');
    document.body.style.userSelect = '';
    document.body.style.cursor = '';
    window.removeEventListener('pointermove', this.boundOnPointerMove);
    window.removeEventListener('pointerup', this.boundStopDragging);
  }

  render() {
    return html`<div class="handle"></div>`;
  }
}

customElements.define('pane-resizer', PaneResizer);
