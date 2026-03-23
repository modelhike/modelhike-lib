import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';
import { moduleToNode } from '../utils/model-tree-builder.js';

export class ModelsPanel extends LitElement {
  static properties = {
    session: { type: Object }
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

    .tree-row.folder {
      color: #cccccc;
      font-weight: 500;
    }

    .tree-row.property,
    .tree-row.method {
      color: #c8c8c8;
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

    .model-badge {
      display: inline-block;
      font-size: 10px;
      line-height: 1;
      padding: 3px 5px;
      border-radius: 999px;
      background: #333;
      color: #dcdcaa;
      margin-left: 6px;
    }
  `;

  renderModelNode(node) {
    const hasChildren = node.children && node.children.length;

    const handleToggle = (e) => {
      e.stopPropagation();
      e.target.classList.toggle('expanded');
      e.target.classList.toggle('collapsed');
      const children = e.target.closest('.tree-node')?.querySelector('.tree-children');
      if (children) {
        children.classList.toggle('collapsed');
        const icon = e.target.closest('.tree-row')?.querySelector('.tree-icon');
        if (icon) {
          icon.textContent = children.classList.contains('collapsed') ? '>' : 'v';
        }
      }
    };

    const handleRowClick = (e) => {
      if (hasChildren) {
        const toggle = e.currentTarget.querySelector('.toggle');
        if (toggle) toggle.click();
      }
    };

    return html`
      <div class="tree-node">
        <div class="tree-row ${hasChildren ? 'folder' : 'file'} ${node.kind || ''}" @click=${handleRowClick}>
          ${hasChildren ? html`
            <span class="toggle expanded" @click=${handleToggle}></span>
            <span class="tree-icon">v</span>
          ` : html`
            <span class="toggle"></span>
            <span class="tree-icon">-</span>
          `}
          <span class="tree-label">${node.label}</span>
          ${node.badge ? html`<span class="model-badge">${node.badge}</span>` : ''}
          ${node.meta ? html`<span class="tree-meta">${node.meta}</span>` : ''}
        </div>
        ${hasChildren ? html`
          <div class="tree-children">
            ${node.children.map(child => this.renderModelNode(child))}
          </div>
        ` : ''}
      </div>
    `;
  }

  render() {
    if (!this.session?.model?.containers?.length) {
      return html`
        <div class="panel-title">Models</div>
        <div class="panel-subtitle">Containers, modules, objects, properties, and methods</div>
        <div class="tree-root">
          <div class="tree-empty">No models loaded</div>
        </div>
      `;
    }

    return html`
      <div class="panel-title">Models</div>
      <div class="panel-subtitle">Containers, modules, objects, properties, and methods</div>
      <div class="tree-root">
        ${this.session.model.containers.map(container => this.renderModelNode({
          kind: 'folder',
          label: container.givenname || container.name || '?',
          meta: container.containerType || 'container',
          badge: 'container',
          children: (container.modules || []).map(moduleToNode)
        }))}
      </div>
    `;
  }
}

customElements.define('models-panel', ModelsPanel);
