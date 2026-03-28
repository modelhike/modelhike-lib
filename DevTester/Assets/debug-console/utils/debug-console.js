/**
 * Lightweight logging wrapper for the debug console UI.
 * Disabled by default. Enable via browser console:
 *   DebugConsole.enable()
 * or by adding ?debug-log to the URL.
 */
class _DebugConsole {
  constructor() {
    this._enabled = new URLSearchParams(location.search).has('debug-log');
  }

  enable()  { this._enabled = true; }
  disable() { this._enabled = false; }
  get isEnabled() { return this._enabled; }

  log(...args)  { if (this._enabled) console.log('[MH]', ...args); }
  warn(...args) { if (this._enabled) console.warn('[MH]', ...args); }
  error(...args) { console.error('[MH]', ...args); }
}

export const DebugConsole = new _DebugConsole();

// Expose on window so it can be toggled from the browser console
window.DebugConsole = DebugConsole;
