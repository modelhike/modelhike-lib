export async function loadSession() {
  const response = await fetch('/api/session');
  return await response.json();
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
