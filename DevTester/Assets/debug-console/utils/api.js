export async function loadSession() {
  const response = await fetch('/api/session');
  return await response.json();
}

export async function loadMode() {
  try {
    const response = await fetch('/api/mode');
    const text = await response.text();
    return JSON.parse(text); // "postMortem" | "stepping"
  } catch {
    return 'postMortem';
  }
}

export async function loadMemory(eventIndex) {
  try {
    const response = await fetch(`/api/memory/${eventIndex}`);
    return await response.json();
  } catch {
    return {};
  }
}

export async function loadSourceFile(fileIdentifier) {
  const response = await fetch(`/api/source/${encodeURIComponent(fileIdentifier)}`);
  if (!response.ok) throw new Error('Source not found');
  return await response.json();
}

export async function loadGeneratedFile(fileIndex) {
  const response = await fetch(`/api/generated-file/${fileIndex}`);
  if (!response.ok) throw new Error('Generated file not found');
  return await response.json();
}

export async function evaluateExpression(expression, eventIndex) {
  const response = await fetch('/api/evaluate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ expression, eventIndex })
  });
  return await response.json();
}

/**
 * Open a WebSocket connection to the debug server.
 *
 * @param {object} handlers
 * @param {function} handlers.onEvent      - called with each DebugEventEnvelope streamed in real time
 * @param {function} handlers.onPaused     - called with { location, vars } when a breakpoint is hit
 * @param {function} handlers.onCompleted  - called when the pipeline finishes
 * @param {function} handlers.onOpen       - called when the socket is connected
 * @param {function} handlers.onClose      - called when the socket closes
 * @returns WebSocket instance (use .send() to send JSON commands back)
 */
export function connectWebSocket({ onEvent, onPaused, onCompleted, onOpen, onClose } = {}) {
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const ws = new WebSocket(`${protocol}//${location.host}/ws`);

  ws.onopen = () => {
    console.log('[WS] connected');
    onOpen?.();
  };

  ws.onmessage = (e) => {
    console.log('[WS] raw message:', e.data.substring(0, 200));
    let msg;
    try { msg = JSON.parse(e.data); } catch (err) { 
      console.warn('[WS] parse error:', err);
      return; 
    }
    console.log('[WS] parsed message type:', msg.type);

    switch (msg.type) {
      case 'event':
        onEvent?.(msg.envelope);
        break;
      case 'paused':
        console.log('[WS] PAUSED!', msg);
        onPaused?.(msg);
        break;
      case 'completed':
        onCompleted?.();
        break;
      default:
        console.log('[WS] unknown message type:', msg.type);
    }
  };

  ws.onclose = () => {
    console.log('[WS] disconnected');
    onClose?.();
  };

  ws.onerror = (err) => {
    console.warn('[WS] error', err);
  };

  return ws;
}

/**
 * Send a stepping command to the server via an open WebSocket.
 */
export function sendResume(ws, mode = 'run') {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'resume', mode }));
  }
}

export function sendAddBreakpoint(ws, fileIdentifier, lineNo) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'addBreakpoint', fileIdentifier, lineNo }));
  }
}

export function sendRemoveBreakpoint(ws, fileIdentifier, lineNo) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'removeBreakpoint', fileIdentifier, lineNo }));
  }
}
