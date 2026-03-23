class AppState {
  constructor() {
    this.session = null;
    this.selectedIndex = 0;
    this.fileWindows = [];
    this.activeSidebarTab = 'trace';
    this.renderToken = 0;
    this.fileTreeFilterIndex = 0;
    this.lastVisibleFileCount = 0;
    this.listeners = new Set();
  }

  setState(updates) {
    Object.assign(this, updates);
    this.notify();
  }

  notify() {
    this.listeners.forEach(fn => fn(this));
  }

  subscribe(callback) {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  getCurrentFileWindow() {
    const windows = this.fileWindows || [];
    if (!windows.length) return null;
    if (this.selectedIndex < windows[0].startIndex) return null;
    let current = windows[0];
    for (const win of windows) {
      if (this.selectedIndex >= win.startIndex) current = win;
      if (this.selectedIndex >= win.startIndex && this.selectedIndex <= win.endIndex) return win;
    }
    return current;
  }

  getVisibleFileWindows() {
    return (this.fileWindows || []).filter(win => win.startIndex <= this.fileTreeFilterIndex);
  }
}

export const state = new AppState();
