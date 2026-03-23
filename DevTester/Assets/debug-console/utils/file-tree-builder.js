import { eventType } from './formatters.js';
import { baseName, rootOutputPath } from './formatters.js';

export function buildFileWindows(session) {
  if (!session) return [];
  
  // If session.files is available (post-mortem mode), use it
  if (session.files && session.files.length > 0) {
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
  
  // Live streaming mode: extract files from events
  if (!session.events || session.events.length === 0) return [];
  
  const files = [];
  session.events.forEach((envelope, i) => {
    const ev = envelope.event;
    // Check for fileGenerated event type
    if (ev && ev.fileGenerated) {
      files.push({
        outputPath: ev.fileGenerated.outputPath,
        templateName: ev.fileGenerated.templateName,
        objectName: ev.fileGenerated.objectName,
        eventIndex: i,
        index: files.length
      });
    }
  });
  
  // Build windows from extracted files
  return files.map((file, i) => {
    const start = file.eventIndex;
    const next = files[i + 1];
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
  if (root && normalized === root) {
    relative = '';
  } else if (root && normalized.startsWith(root + '/')) {
    relative = normalized.slice(root.length + 1);
  } else if (root && normalized.startsWith(root)) {
    // Handle case where root doesn't end with / but path continues
    relative = normalized.slice(root.length).replace(/^\//, '');
  }
  
  const parts = relative.split('/').filter(Boolean);
  return parts.length ? parts : [baseName(normalized)];
}

// Find the common output directory from file paths
// This looks for a typical output folder structure
function findCommonRoot(paths) {
  if (!paths || paths.length === 0) return '';
  
  const normalized = paths.map(p => String(p || '').replace(/\\/g, '/'));
  const splitPaths = normalized.map(p => p.split('/').filter(Boolean));
  
  if (splitPaths.length === 0) return '';
  
  // Find common prefix parts
  const commonParts = [];
  const minLen = Math.min(...splitPaths.map(p => p.length));
  
  for (let i = 0; i < minLen; i++) {
    const part = splitPaths[0][i];
    if (splitPaths.every(p => p[i] === part)) {
      commonParts.push(part);
    } else {
      break;
    }
  }
  
  // Remove the last part if all files share the same final filename (unlikely)
  // Keep at least one folder in the common root
  if (commonParts.length > 1) {
    // Check if the last common part is actually a file (exists in all paths at same position)
    const lastPartIndex = commonParts.length - 1;
    const isLastPartAFile = splitPaths.every(p => p.length === lastPartIndex + 1);
    if (isLastPartAFile) {
      commonParts.pop();
    }
  }
  
  return commonParts.length ? '/' + commonParts.join('/') : '';
}

export function buildFileTree(session, fileWindows) {
  if (!fileWindows || fileWindows.length === 0) {
    return { kind: 'folder', name: 'output', children: {}, isRoot: true };
  }
  
  // Get all file paths
  const paths = fileWindows.map(w => w.outputPath).filter(Boolean);
  if (paths.length === 0) {
    return { kind: 'folder', name: 'output', children: {}, isRoot: true };
  }
  
  // Try session config first for the root path
  let rootPath = rootOutputPath(session);
  
  // If no config root, compute from file paths
  if (!rootPath) {
    rootPath = findCommonRoot(paths);
  }
  
  // Validate that rootPath actually matches the files
  // If it doesn't prefix any file, recompute
  if (rootPath && !paths.some(p => p.startsWith(rootPath))) {
    rootPath = findCommonRoot(paths);
  }
  
  const rootName = baseName(rootPath) || 'output';
  const root = { kind: 'folder', name: rootName, children: {}, isRoot: true };
  
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
