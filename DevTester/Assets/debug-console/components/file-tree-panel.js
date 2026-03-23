import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { unsafeHTML } from 'https://cdn.jsdelivr.net/npm/lit-html@3/directives/unsafe-html.js/+esm';
import { baseName, rootOutputPath } from '../utils/formatters.js';
import { buildFileTree, sortTreeChildren, fileIconSVG, folderIconSVG } from '../utils/file-tree-builder.js';

export class FileTreePanel extends LitElement {
  static properties = {
    session: { type: Object },
    visibleFileWindows: { type: Array },
    currentWindow: { type: Object },
    totalFileWindows: { type: Number },
    lastVisibleFileCount: { type: Number, state: true }
  };

  static styles = css`
    :host {
      display: block;
      padding: 0;
      height: 100%;
      overflow: auto;
    }

    :host::-webkit-scrollbar {
      width: 8px;
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

    .panel-title {
      font-weight: 600;
      margin-bottom: 8px;
      color: #9cdcfe;
      padding: 8px 8px 0;
    }

    .panel-subtitle {
      font-size: 11px;
      color: #858585;
      margin-bottom: 8px;
      padding: 0 8px;
    }

    .tree-root {
      font-size: 12px;
      padding: 0 0 6px;
    }

    .tree-node {
      margin-left: 0;
    }

    .tree-row {
      display: flex;
      align-items: center;
      gap: 4px;
      padding: 2px 8px;
      min-height: 22px;
      border-radius: 0;
      cursor: pointer;
    }

    .tree-row:hover {
      background: #2a2d2e;
    }

    .tree-row.selected {
      background: #094771;
    }

    .tree-row.folder {
      color: #cccccc;
      font-weight: 500;
    }

    .tree-row.file {
      color: #d4d4d4;
    }

    .tree-label {
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .tree-meta {
      margin-left: auto;
      color: #7f848e;
      font-size: 10px;
    }

    .tree-children {
      margin-left: 12px;
    }

    .tree-children.collapsed {
      display: none;
    }

    .tree-empty {
      color: #858585;
      font-size: 12px;
      padding: 0 8px 6px;
    }

    .tree-icon {
      width: 14px;
      flex: 0 0 14px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: #7f848e;
      font-size: 10px;
    }

    .tree-icon svg {
      width: 14px;
      height: 14px;
      display: block;
    }

    .tree-row.file .toggle {
      visibility: hidden;
    }

    .toggle {
      display: inline-block;
      width: 1em;
      margin-right: 4px;
      cursor: pointer;
      user-select: none;
    }

    .toggle.collapsed::before {
      content: '▶';
    }

    .toggle.expanded::before {
      content: '▼';
    }
  `;

  constructor() {
    super();
    this.lastVisibleFileCount = 0;
  }

  updated(changedProperties) {
    if (changedProperties.has('visibleFileWindows')) {
      const visibleCount = this.visibleFileWindows?.length || 0;
      if (visibleCount === 0 && this.lastVisibleFileCount !== 0) {
        this.scrollTop = 0;
      }
      if (visibleCount < this.lastVisibleFileCount) {
        this.scrollTop = 0;
      }
      this.lastVisibleFileCount = visibleCount;
    }
  }

  renderTreeNode(node, isCurrentFile) {
    const isFolder = node.kind === 'folder';
    const isSelected = node.fileWindow && this.currentWindow && node.fileWindow.index === this.currentWindow.index;

    const handleToggle = (e) => {
      e.stopPropagation();
      const toggle = e.target;
      toggle.classList.toggle('expanded');
      toggle.classList.toggle('collapsed');
      const treeNode = toggle.closest('.tree-node');
      const children = treeNode?.querySelector('.tree-children');
      if (children) {
        children.classList.toggle('collapsed');
        const icon = treeNode?.querySelector('.tree-row .tree-icon');
        if (icon && isFolder) {
          const isOpen = !children.classList.contains('collapsed');
          icon.innerHTML = folderIconSVG(isOpen);
        }
      }
    };

    const handleRowClick = (e) => {
      if (isFolder) {
        const toggle = e.currentTarget.querySelector('.toggle');
        if (toggle) toggle.click();
      } else if (node.fileWindow) {
        this.dispatchEvent(new CustomEvent('file-selected', {
          detail: { fileWindow: node.fileWindow },
          bubbles: true,
          composed: true
        }));
      }
    };

    return html`
      <div class="tree-node">
        <div class="tree-row ${node.kind} ${isSelected ? 'selected' : ''}" @click=${handleRowClick}>
          ${isFolder ? html`
            <span class="toggle expanded" @click=${handleToggle}></span>
            <span class="tree-icon">${unsafeHTML(folderIconSVG(true))}</span>
          ` : html`
            <span class="toggle"></span>
            <span class="tree-icon">${unsafeHTML(fileIconSVG())}</span>
          `}
          <span class="tree-label">${node.name}</span>
          ${node.fileWindow ? html`
            <span class="tree-meta">${node.fileWindow.eventCount} ev</span>
          ` : ''}
        </div>
        ${isFolder && Object.keys(node.children || {}).length ? html`
          <div class="tree-children">
            ${sortTreeChildren(node.children).map(child => this.renderTreeNode(child, isCurrentFile))}
          </div>
        ` : ''}
      </div>
    `;
  }

  render() {
    const rootPath = this.session ? rootOutputPath(this.session) : '';
    const visibleCount = this.visibleFileWindows?.length || 0;

    if (!visibleCount) {
      return html`
        <div class="panel-title">Generated Files</div>
        <div class="panel-subtitle">No files generated yet at this timeline position</div>
        <div class="tree-root">
          <div class="tree-empty">No generated files recorded</div>
        </div>
      `;
    }

    const metaText = `Root: ${baseName(rootPath) || 'output'} · showing ${visibleCount} of ${this.totalFileWindows} files${this.currentWindow ? ' · selected: ' + baseName(this.currentWindow.outputPath) : ''}`;

    const tree = buildFileTree(this.session, this.visibleFileWindows);

    return html`
      <div class="panel-title">Generated Files</div>
      <div class="panel-subtitle">${metaText}</div>
      <div class="tree-root">
        ${this.renderTreeNode(tree, false)}
      </div>
    `;
  }
}

customElements.define('file-tree-panel', FileTreePanel);
