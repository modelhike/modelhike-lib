import { eventType } from './formatters.js';
import { baseName, rootOutputPath } from './formatters.js';

export function buildFileWindows(session) {
  if (!session || !session.files) return [];
  return session.files.map((file, i) => {
    const start = file.eventIndex;
    const next = session.files[i + 1];
    const end = next ? Math.max(start, next.eventIndex - 1) : Math.max(start, session.events.length - 1);
    const events = session.events.slice(start, end + 1);
    return {
      ...file,
      index: i,
      startIndex: start,
      endIndex: end,
      eventCount: events.length,
      controlFlowCount: events.filter(ev => eventType(ev) === 'controlFlow').length,
      templateCount: events.filter(ev => eventType(ev) === 'templateStarted').length
    };
  });
}

export function relativePathParts(path, rootPath) {
  const normalized = String(path || '').replace(/\\/g, '/');
  const root = String(rootPath || '').replace(/\\/g, '/').replace(/\/+$/, '');
  let relative = normalized;
  if (root && normalized === root) relative = '';
  else if (root && normalized.startsWith(root + '/')) relative = normalized.slice(root.length + 1);
  const parts = relative.split('/').filter(Boolean);
  return parts.length ? parts : [baseName(normalized)];
}

export function buildFileTree(session, fileWindows) {
  const rootPath = rootOutputPath(session);
  const root = { kind: 'folder', name: baseName(rootPath) || 'output', children: {}, isRoot: true };
  fileWindows.forEach(win => {
    const parts = relativePathParts(win.outputPath, rootPath);
    let cursor = root;
    parts.forEach((part, idx) => {
      const isLeaf = idx === parts.length - 1;
      if (!cursor.children[part]) {
        cursor.children[part] = {
          kind: isLeaf ? 'file' : 'folder',
          name: part,
          children: {},
          fileWindow: null
        };
      }
      if (isLeaf) {
        cursor.children[part].fileWindow = win;
      }
      cursor = cursor.children[part];
    });
  });
  return root;
}

export function sortTreeChildren(children) {
  return Object.values(children || {}).sort((a, b) => {
    if (a.kind !== b.kind) return a.kind === 'folder' ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
}

export function fileIconSVG() {
  return '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="#c5c5c5" d="M4 1.75h5.5L13 5.25V14.5a.75.75 0 0 1-.75.75h-8.5A.75.75 0 0 1 3 14.5v-12A.75.75 0 0 1 3.75 1.75H4Zm5 .75v3h3"/></svg>';
}

export function folderIconSVG(isOpen) {
  const fill = isOpen ? '#dcb67a' : '#cfa25e';
  return '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="' + fill + '" d="M1.75 3.5A1.75 1.75 0 0 1 3.5 1.75h2.61c.4 0 .78.14 1.08.4l1.01.85h4.3c.97 0 1.75.78 1.75 1.75v.7H1.75V3.5Zm0 2.7h12.5v6.3c0 .97-.78 1.75-1.75 1.75H3.5a1.75 1.75 0 0 1-1.75-1.75V6.2Z"/></svg>';
}
