export function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function baseName(path) {
  const parts = String(path || '').split('/').filter(Boolean);
  return parts[parts.length - 1] || path || '?';
}

export function compactPath(path) {
  if (!path) return '?';
  const parts = String(path).split('/').filter(Boolean);
  if (parts.length <= 3) return parts.join('/');
  return parts.slice(-3).join('/');
}

export function eventType(ev) {
  return Object.keys(ev.event)[0];
}

export function eventPayload(ev) {
  return Object.values(ev.event)[0];
}

export function eventLabel(ev) {
  const t = eventType(ev);
  const v = eventPayload(ev);
  if (t === 'fileGenerated') return '📁 ' + v.outputPath;
  if (t === 'fileCopied') return '📋 ' + v.outputPath;
  if (t === 'controlFlow') return '🔀 ' + v.condition;
  if (t === 'phaseStarted') return '▶ ' + v.name;
  if (t === 'phaseCompleted') return '✓ ' + v.name;
  if (t === 'workingDirChanged') return '📂 ' + v.to;
  if (t === 'templateStarted') return '📄 ' + v.name;
  if (t === 'scriptStarted') return '📜 ' + v.name;
  return t;
}

export function getSourceLocation(ev) {
  const e = ev.event;
  const v = Object.values(e)[0];
  return v && v.source ? v.source : null;
}

export function hasValidSourceLocation(loc) {
  return !!(loc && loc.fileIdentifier && loc.lineNo > 0);
}

export function rootOutputPath(session) {
  return String(session?.config?.outputPath || '').replace(/\\/g, '/').replace(/\/+$/, '');
}
