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

/**
 * Returns a human-readable icon + label string for any DebugEvent variant.
 * Covers all 30+ cases declared in DebugEvent.swift.
 */
export function eventLabel(ev) {
  const t = eventType(ev);
  const v = eventPayload(ev) || {};

  // --- File events ---
  if (t === 'fileGenerated')         return '📁 ' + (v.outputPath || v.name || '?');
  if (t === 'fileCopied')            return '📋 ' + (v.outputPath || v.name || '?');
  if (t === 'fileSkipped')           return '⏭ ' + (v.path || v.name || '?') + (v.reason ? ` (${v.reason})` : '');
  if (t === 'fileExcluded')          return '🚫 ' + (v.path || '?') + (v.reason ? ` — ${v.reason}` : '');
  if (t === 'renderingStopped')      return '🛑 stopped: ' + (v.path || '?');
  if (t === 'renderingThrewError')   return '❌ throw: ' + (v.path || '?');

  // --- Folder events ---
  if (t === 'folderRendered')        return '📂 rendered → ' + (v.toPath || v.name || '?');
  if (t === 'folderCopied')          return '📂 copied → ' + (v.toPath || v.name || '?');

  // --- Control flow ---
  if (t === 'controlFlow')           return '🔀 ' + (v.condition || v.keyword || '?');
  if (t === 'loopStarted')           return '🔁 for ' + (v.expression || '?');
  if (t === 'loopIteration')         return '  ↩ ' + (v.index !== undefined ? `[${v.index}]` : '');
  if (t === 'loopCompleted')         return '✓ for ' + (v.expression || '?');

  // --- Phase lifecycle ---
  if (t === 'phaseStarted')          return '▶ phase: ' + v.name;
  if (t === 'phaseCompleted')        return '✓ phase: ' + v.name + (v.duration != null ? ` (${v.duration.toFixed(2)}s)` : '');
  if (t === 'phaseFailed')           return '❌ phase: ' + v.name;
  if (t === 'pipelineStarted')       return '🚀 pipeline started';
  if (t === 'pipelineCompleted')     return '🏁 pipeline done';

  // --- Script / template lifecycle ---
  if (t === 'scriptStarted')         return '📜 script: ' + (v.name || '?');
  if (t === 'scriptCompleted')       return '✅ script: ' + (v.name || '?');
  if (t === 'templateStarted')       return '📄 template: ' + (v.name || '?');
  if (t === 'templateCompleted')     return '✅ template: ' + (v.name || '?');

  // --- Variables ---
  if (t === 'variableSet') {
    const arrow = v.oldValue != null ? `${JSON.stringify(v.oldValue)} → ` : '';
    return '📌 ' + (v.name || '?') + ': ' + arrow + JSON.stringify(v.newValue ?? null);
  }
  if (t === 'variableCleared')       return '🗑 clear ' + (v.name || '?');
  if (t === 'workingDirChanged')     return '📂 workdir → ' + (v.to || '(base)');
  if (t === 'snapshotPushed')        return '📥 snapshot push';
  if (t === 'snapshotPopped')        return '📤 snapshot pop';

  // --- Evaluation ---
  if (t === 'expressionEvaluated')   return '🔢 ' + (v.expression || '?') + ' → ' + JSON.stringify(v.result ?? null);
  if (t === 'modifierApplied')       return '🔧 |' + (v.name || '?');

  // --- Debug output ---
  if (t === 'consoleLog')            return '🏷 ' + (v.value || '?');
  if (t === 'announce')              return '🔈 ' + (v.value || '?');
  if (t === 'parsedTreeDumped')      return '🌲 ' + (v.treeName || '?');

  // --- Model ---
  if (t === 'modelLoaded')           return '📦 model loaded — containers: ' + (v.containerCount ?? '?') + ', types: ' + (v.typeCount ?? '?');
  if (t === 'containerStarted')      return '🗂 container: ' + (v.name || '?');

  // --- Diagnostics ---
  if (t === 'diagnostic') {
    const sev = v.severity || 'info';
    const icon = sev === 'error' ? '❌' : sev === 'warning' ? '⚠️' : sev === 'hint' ? '💡' : 'ℹ️';
    const code = v.code ? `[${v.code}] ` : '';
    return `${icon} ${code}${v.message || '?'}`;
  }

  // --- Errors ---
  if (t === 'error') {
    const code = v.code ? `[${v.code}] ` : '';
    const category = v.category ? `${v.category}: ` : '';
    return '❌ ' + code + category + (v.message || '?');
  }

  // --- Fallback: show raw type name ---
  return '• ' + t;
}

/**
 * Returns a CSS class name for colour-coding trace events.
 */
export function eventCssClass(ev) {
  const t = eventType(ev);
  if (t === 'error') return 'trace-error';
  if (t === 'diagnostic') {
    const sev = (eventPayload(ev) || {}).severity || 'info';
    return `trace-diagnostic trace-diagnostic--${sev}`;
  }
  if (t === 'phaseStarted' || t === 'phaseCompleted' || t === 'phaseFailed') return 'trace-phase';
  if (t === 'fileGenerated' || t === 'fileCopied') return 'trace-file';
  if (t === 'consoleLog' || t === 'announce') return 'trace-log';
  if (t === 'scriptStarted' || t === 'scriptCompleted') return 'trace-script';
  if (t === 'templateStarted' || t === 'templateCompleted') return 'trace-template';
  return '';
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
