# ModelHike Debug Console

## Overview

The debug console is a browser-based visual debugger for ModelHike pipeline runs. It provides post-mortem inspection of code generation sessions including:

- **Event traces** - Every template parse, execution, control flow decision
- **Variable state** - Captured snapshots of template variables at file generation
- **Model hierarchy** - Browse containers, modules, entities, DTOs
- **Generated files** - View output content alongside the template source
- **Expression evaluation** - Test expressions against captured state

The console uses a modular architecture with Lit web components loaded from CDN - no build step required.

## Quick Start

```bash
# Run pipeline with debug enabled
swift run DevTester --debug --debug-dev --no-open --debug-port=4800

# Open browser
open http://localhost:4800
```

---

## Architecture

### Technology Stack

| Technology | Purpose |
|------------|---------|
| **Lit 3.x** | Lightweight web components (loaded from CDN) |
| **ES6 Modules** | Native browser imports, no bundler |
| **Shadow DOM** | Component style encapsulation |
| **CSS Variables** | Theme customization (`--left-sidebar-width`, etc.) |

### Directory Structure

```
debug-console/
├── index.html                 # Entry point (loads debug-app.js)
├── styles/
│   ├── base.css              # Reset, CSS variables, scrollbar styling
│   ├── layout.css            # Grid definitions, panel classes
│   └── themes.css            # VS Code dark theme colors
├── components/
│   ├── debug-app.js          # Root orchestrator
│   ├── header-bar.js         # Top bar with phases
│   ├── summary-bar.js        # Metrics ribbon
│   ├── file-tree-panel.js    # Left sidebar file explorer
│   ├── source-editor.js      # Template source viewer
│   ├── output-editor.js      # Generated output viewer
│   ├── trace-panel.js        # Event trace list
│   ├── variables-panel.js    # Variable inspector
│   ├── models-panel.js       # Model hierarchy browser
│   ├── footer-bar.js         # Timeline + expression eval
│   ├── pane-resizer.js       # Draggable divider
│   └── code-panel.js         # Reusable code display
└── utils/
    ├── api.js                # Fetch wrappers for /api/* endpoints
    ├── state.js              # Centralized AppState singleton
    ├── formatters.js         # escapeHtml, baseName, eventLabel, etc.
    ├── file-tree-builder.js  # buildFileWindows, buildFileTree
    └── model-tree-builder.js # buildModelTree
```

### Component Hierarchy

```
<debug-app>                    ← Root: loads session, manages state
├── <header-bar>               ← Logo + phase indicators
├── <summary-bar>              ← Event/file/model counts
├── <file-tree-panel>          ← Left sidebar
├── <pane-resizer>             ← Draggable left divider
├── <source-editor>            ← Top center panel
│   └── <code-panel>           ← Reusable code display
├── <output-editor>            ← Bottom center panel
│   └── <code-panel>
├── <pane-resizer>             ← Draggable right divider
├── [Right sidebar tabs]
│   ├── <trace-panel>          ← Event list
│   ├── <variables-panel>      ← Variable inspector
│   └── <models-panel>         ← Model tree
└── <footer-bar>               ← Timeline + eval input
```

---

## Component Reference

### `<debug-app>` - Root Orchestrator

**File:** `components/debug-app.js`

The root component that orchestrates the entire debug console.

**Responsibilities:**
- Fetches session data on mount via `loadSession()`
- Builds file windows from session using `buildFileWindows()`
- Manages centralized state and syncs to child components
- Handles all custom events from children (file-selected, event-selected, timeline-changed)
- Renders the main grid layout

**Properties (internal state):**
| Property | Type | Description |
|----------|------|-------------|
| `session` | Object | Full debug session from `/api/session` |
| `selectedIndex` | Number | Currently selected event index |
| `currentWindow` | Object | Current file window (contains outputPath, startIndex, etc.) |
| `visibleFileWindows` | Array | File windows visible at current timeline position |
| `activeSidebarTab` | String | 'trace' \| 'variables' \| 'models' |

**Event Handlers:**
- `@file-selected` → Updates selectedIndex to file's startIndex
- `@event-selected` → Updates selectedIndex
- `@timeline-changed` → Updates selectedIndex and fileTreeFilterIndex

---

### `<header-bar>` - Header with Phase Indicators

**File:** `components/header-bar.js`

Displays the ModelHike logo and pipeline phase status.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `phases` | Array | Phase records from session (name, success, duration) |

**Rendering:**
- Shows "ModelHike Debug Console" title
- Renders each phase as a pill with name and status color
- Completed phases shown in blue, failed in red

---

### `<summary-bar>` - Metrics Ribbon

**File:** `components/summary-bar.js`

Displays key metrics about the debug session.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `session` | Object | Debug session |
| `currentWindow` | Object | Currently selected file window |
| `fileWindowsCount` | Number | Total number of generated files |

**Displays:**
- Total event count
- Generated file count
- Model count (containers + entities)
- Current file name (if selected)

---

### `<file-tree-panel>` - File Explorer

**File:** `components/file-tree-panel.js`

Scrollable tree view of generated files with folder hierarchy.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `session` | Object | Debug session (for root path extraction) |
| `visibleFileWindows` | Array | Files to display (filtered by timeline) |
| `currentWindow` | Object | Currently selected file (for highlighting) |
| `totalFileWindows` | Number | Total files (for "showing X of Y" text) |

**Events Emitted:**
| Event | Detail | Description |
|-------|--------|-------------|
| `file-selected` | `{ fileWindow }` | User clicked a file |

**Features:**
- Builds tree structure from flat file list using `buildFileTree()`
- Collapsible folders with toggle arrows
- SVG icons for files and folders (uses `unsafeHTML` directive)
- Highlights currently selected file
- Shows event count per file
- Scrollable with styled scrollbar

---

### `<source-editor>` - Template Source Viewer

**File:** `components/source-editor.js`

Displays the template source file for the current selection.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `session` | Object | Debug session (for event lookup) |
| `selectedIndex` | Number | Current event index |
| `currentWindow` | Object | Current file window (for template name) |

**Internal State:**
- `sourceContent` - Fetched source text
- `sourceIdentifier` - Display name for the source file
- `highlightLine` - Line number to highlight
- `renderToken` - Async cancellation token

**Data Flow:**
1. When `selectedIndex` or `currentWindow` changes, calls `loadSource()`
2. Determines source identifier from current window's template name or event's source location
3. Fetches from `/api/source/:identifier`
4. Renders via `<code-panel>` with line highlighting

---

### `<output-editor>` - Generated Output Viewer

**File:** `components/output-editor.js`

Displays the generated file content for the current selection.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `currentWindow` | Object | Current file window |

**Internal State:**
- `outputContent` - Fetched generated content
- `outputPath` - Display path
- `renderToken` - Async cancellation token

**Data Flow:**
1. When `currentWindow` changes, calls `loadOutput()`
2. Fetches from `/api/generated-file/:index`
3. Renders via `<code-panel>`

---

### `<trace-panel>` - Event Trace List

**File:** `components/trace-panel.js`

Displays the list of debug events for the current file window.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `session` | Object | Debug session (for events array) |
| `currentWindow` | Object | Current file window (defines event range) |
| `selectedIndex` | Number | Currently selected event (for highlighting) |

**Events Emitted:**
| Event | Detail | Description |
|-------|--------|-------------|
| `event-selected` | `{ index }` | User clicked an event |

**Features:**
- Filters events to current file window's range (startIndex to endIndex)
- Color-coded event types (controlFlow, templateStarted, fileGenerated, etc.)
- Shows event label and source location
- Highlights selected event
- Scrollable list

---

### `<variables-panel>` - Variable Inspector

**File:** `components/variables-panel.js`

Displays variable state captured at the current event index.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `selectedIndex` | Number | Current event index |

**Internal State:**
- `variables` - Object of variable name → value pairs
- `loading` - Loading indicator state

**Data Flow:**
1. When `selectedIndex` changes, fetches `/api/memory/:index`
2. Displays variables in a sorted table
3. Filters out internal variables (starting with `@`)

**Note:** Variables are only captured when files are generated. Events before the first file generation will show "No variables".

---

### `<models-panel>` - Model Hierarchy Browser

**File:** `components/models-panel.js`

Displays the model hierarchy (containers, modules, entities).

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `session` | Object | Debug session (contains model snapshot) |

**Features:**
- Builds tree from session's model snapshot using `buildModelTree()`
- Three-level hierarchy: Container → Module → Entity/DTO
- Collapsible nodes
- Shows entity annotations and tags
- Shows property counts per entity

---

### `<footer-bar>` - Timeline & Expression Evaluator

**File:** `components/footer-bar.js`

Bottom bar with timeline slider and expression evaluation input.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `session` | Object | Debug session |
| `selectedIndex` | Number | Current event index |
| `currentWindow` | Object | Current file window |
| `fileWindowsCount` | Number | Total files |

**Events Emitted:**
| Event | Detail | Description |
|-------|--------|-------------|
| `timeline-changed` | `{ index }` | User dragged timeline slider |

**Features:**
- Timeline slider (0 to total events)
- Expression input field
- Evaluates expressions via POST to `/api/evaluate`
- Displays evaluation result or error

---

### `<pane-resizer>` - Draggable Panel Divider

**File:** `components/pane-resizer.js`

Vertical draggable handle for resizing adjacent panels.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `cssVar` | String | CSS variable to update (e.g., `--left-sidebar-width`) |
| `mode` | String | 'left' or 'right' - determines resize direction |

**Behavior:**
- Listens for `pointerdown` on the component
- On drag, updates the specified CSS variable on `document.documentElement`
- Clamps width between 220px and 45% of viewport
- Shows visual handle indicator on hover

---

### `<code-panel>` - Reusable Code Display

**File:** `components/code-panel.js`

Reusable component for displaying code with line numbers.

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `content` | String | Code content to display |
| `highlightLine` | Number | Line number to highlight (1-indexed) |
| `emptyMessage` | String | Message when content is empty |

**Features:**
- Splits content into lines
- Renders line numbers in gutter
- Highlights specified line with background color
- Scrollable with styled scrollbar
- Escapes HTML in code content

---

## Utility Modules

### `utils/api.js` - API Client

Provides async functions for fetching data from the debug server:

```javascript
loadSession()              // GET /api/session
loadMemory(eventIndex)     // GET /api/memory/:index
loadSourceFile(identifier) // GET /api/source/:id
loadGeneratedFile(index)   // GET /api/generated-file/:index
evaluateExpression(expr, eventIndex) // POST /api/evaluate
```

### `utils/state.js` - Centralized State

Singleton `AppState` class managing global state:

```javascript
class AppState {
  session = null;
  selectedIndex = 0;
  fileWindows = [];
  activeSidebarTab = 'trace';
  fileTreeFilterIndex = 0;
  
  setState(updates)        // Merge updates and notify
  getCurrentFileWindow()   // Get file window containing selectedIndex
  getVisibleFileWindows()  // Get files visible at fileTreeFilterIndex
}

export const state = new AppState();
```

### `utils/formatters.js` - Text Helpers

Pure functions for formatting:

```javascript
escapeHtml(s)          // Escape HTML entities
baseName(path)         // Extract filename from path
compactPath(path)      // Shorten long paths
eventType(ev)          // Get event type key
eventPayload(ev)       // Get event payload
eventLabel(ev)         // Human-readable event label
rootOutputPath(session)// Extract output root from session
getSourceLocation(ev)  // Extract source location from event
hasValidSourceLocation(loc) // Check if location is valid
```

### `utils/file-tree-builder.js` - Tree Construction

Functions for building file tree structure:

```javascript
buildFileWindows(session)      // Convert session.files to file windows
relativePathParts(path, root)  // Split path relative to root
buildFileTree(session, files)  // Build nested tree structure
sortTreeChildren(children)     // Sort folders before files
fileIconSVG()                  // SVG string for file icon
folderIconSVG(isOpen)          // SVG string for folder icon
```

### `utils/model-tree-builder.js` - Model Tree

Functions for building model hierarchy:

```javascript
buildModelTree(session) // Convert model snapshot to tree structure
```

---

## State Management

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         debug-app                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    AppState (singleton)                      ││
│  │  session, selectedIndex, fileWindows, activeSidebarTab       ││
│  └─────────────────────────────────────────────────────────────┘│
│         │                    │                    │              │
│         ▼                    ▼                    ▼              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐          │
│  │ file-tree   │    │  source-    │    │   trace-    │          │
│  │   panel     │    │   editor    │    │   panel     │          │
│  └─────────────┘    └─────────────┘    └─────────────┘          │
│         │                                     │                  │
│         │ file-selected event                 │ event-selected   │
│         └─────────────────────────────────────┘                  │
│                           │                                      │
│                           ▼                                      │
│                   debug-app.handleEvent()                        │
│                   state.setState({ selectedIndex })              │
│                   debug-app.syncFromState()                      │
└─────────────────────────────────────────────────────────────────┘
```

### Event Flow

1. User interaction in child component (e.g., click file)
2. Child dispatches CustomEvent with `bubbles: true, composed: true`
3. Parent (`debug-app`) handles event
4. Parent updates centralized state
5. Parent calls `syncFromState()` to update its properties
6. Lit reactively updates child components via property binding

---

## Performance Patterns

### Render Token Pattern

Prevents stale async results from overwriting newer data:

```javascript
async loadSource() {
  const token = ++this.renderToken;  // Increment token
  const data = await fetchData();
  if (token !== this.renderToken) return;  // Stale, discard
  this.content = data;  // Safe to update
}
```

### Lazy Loading

Components fetch their own data when properties change:

```javascript
async updated(changedProperties) {
  if (changedProperties.has('selectedIndex')) {
    await this.loadData();  // Only fetch when needed
  }
}
```

---

## Development

### No Build Step

All files served as-is. Lit loaded from CDN:

```html
<script type="module" src="components/debug-app.js"></script>
```

### Adding a Component

1. Create `components/my-component.js`:

```javascript
import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';

export class MyComponent extends LitElement {
  static properties = {
    data: { type: Object }
  };

  static styles = css`
    :host { display: block; }
  `;

  render() {
    return html`<div>${this.data}</div>`;
  }
}

customElements.define('my-component', MyComponent);
```

2. Import in parent: `import './my-component.js';`
3. Use in template: `html\`<my-component .data=\${this.myData}></my-component>\``

### Debugging

- **Browser DevTools** - Works natively, no source maps needed
- **Lit DevTools** - Chrome extension for component inspection
- **Network tab** - See all module loads and API calls
- **Console** - Errors include proper stack traces

## Development

### No Build Step Required
All files are served as-is. The browser natively handles ES6 module imports and Lit is loaded from CDN:
```html
<script type="module" src="components/debug-app.js"></script>
```

### Adding a New Component
1. Create `components/my-component.js`:
```javascript
import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3/+esm';

export class MyComponent extends LitElement {
  static properties = {
    data: { type: Object }
  };

  render() {
    return html`<div>${this.data}</div>`;
  }
}

customElements.define('my-component', MyComponent);
```

2. Import in parent component:
```javascript
import './my-component.js';
```

3. Use in template:
```javascript
html`<my-component .data=${this.myData}></my-component>`
```

### Debugging
- Browser DevTools work natively with source maps
- Component state visible in Lit DevTools extension
- Network tab shows all module loads
- Console shows all errors with proper stack traces

## Server Integration

`DebugHTTPServer.swift` serves the modular console:
- `/` - Serves `debug-console/index.html`
- `/styles/*` - CSS files with `text/css` MIME type
- `/components/*` - JS modules with `application/javascript` MIME type
- `/utils/*` - JS utility modules
- `/api/*` - Debug session data endpoints

### API Endpoints
| Endpoint | Description |
|----------|-------------|
| `/api/session` | Full session data (events, files, config) |
| `/api/events` | Event list |
| `/api/files` | Generated file list |
| `/api/model` | Model hierarchy snapshot |
| `/api/memory/:index` | Variable state at event index |
| `/api/source/:id` | Template source content |
| `/api/generated-file/:index` | Generated file content |
| `/api/evaluate` | Expression evaluation (POST)

## UI Features

### Panels
- **Left Sidebar**: Scrollable file tree with folder/file icons
- **Center Split**: Template source (top) and generated output (bottom)
- **Right Sidebar**: Tabbed view (Trace, Variables, Models)
- **Footer**: Expression evaluator and timeline slider

### Interactions
- **File Selection**: Click file in tree to view source/output
- **Panel Resizing**: Drag vertical handles between panels
- **Tab Navigation**: Switch between Trace/Variables/Models
- **Timeline Scrubbing**: Drag slider to navigate events
- **Expression Eval**: Type expressions in footer input

### Styling
- VS Code dark theme colors
- Custom scrollbars (dark track, subtle thumb)
- Monospace font throughout
- Hover/selected states on interactive elements

## Benefits

1. **Maintainability**: Each component has single responsibility
2. **Reusability**: Shared components (`code-panel`, `pane-resizer`)
3. **Testability**: Pure utility functions are unit-testable
4. **Developer Experience**: Modern patterns, better IDE support
5. **No Tooling**: Zero build step, instant development cycle
6. **Performance**: Reactive updates, only re-render what changed

## Known Limitations

- **Variables**: Only captured when files are generated (not continuously tracked)
- **No syntax highlighting**: Code shown as plain text with line numbers
- **No search**: Cannot search within files or events yet

## Future Enhancements

Potential improvements:
- Add syntax highlighting (Prism.js or Shiki)
- Add virtual scrolling for large event lists
- Add search/filter capabilities
- Add continuous variable tracking
- Add export/download features
- Add TypeScript for type safety
