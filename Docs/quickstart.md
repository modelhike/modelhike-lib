# ModelHike Quickstart Guide

Welcome to ModelHike. ModelHike is the intent compiler for the AI era. Generate deterministic system diagrams and production-ready code from a single declarative intent.
> You’re on a hike through your system’s architecture. ModelHike is the **trail map, compass, and lookout points** — all in one. You control the pace. The path is clear.

## 🧭 Why ModelHike?

Most architecture tools are either:

- **Too rigid** (low-code platforms that fight your flow)
- **Too loose** (spec-driven AI tools that guess your intent and hallucinate code)
- **Too complicated** (enterprise UML monsters that nobody enjoys using)

ModelHike gives you:

✅ **Intent-native development:** A Markdown-inspired DSL that acts as the single source of truth.
✅ **Compilation, not generation:** 100% deterministic code generation. Same intent twice = same code twice.
✅ **Diff the why, not the what:** Shrink the review surface. You diff 20 lines of why, not 500 files of generated what.
✅ **AI in the Loop:** Let your AI author the intent. The compiler handles the rest.

Think of it like this:

> **Source intent is the new source code.** Code is downstream now. ModelHike lets you control the intent while the compiler automates the implementation.

---

## 1. 👋 Quick Ascent (Quickstart)

Get started with ModelHike in a few simple steps—no mountaineering gear needed.

### Prerequisites

- macOS 13+ or Linux
- Swift 6.0 or later

### Installation

**As a Swift Package dependency:**

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/modelhike/modelhike.git", branch: "main")
]
```

**From source:**

```bash
git clone https://github.com/modelhike/modelhike.git
cd modelhike
swift build
```

### Running the DevTester

The `DevTester` executable runs the full code generation pipeline:

```bash
swift run DevTester
```

> **Note:** DevTester requires a `modelhike-blueprints` repository alongside this repo. See `DevTester/Environment.swift` for path configuration.

### Visual Debugging

Launch the browser-based debugger to inspect pipeline runs:

```bash
# Post-mortem mode: pipeline runs, then browse results
swift run DevTester --debug --debug-dev

# Live stepping: watch events stream in real time
swift run DevTester --debug-stepping --debug-dev
```

Then open `http://localhost:4800` in your browser.

> **In just seconds**, see a basic full-stack app spinning up—feel that excitement of first 
light on the trail.
---

## 2. 🌟 Trailhead (What is ModelHike?)

### Your friendly path into full-stack creation

> **Start with AI. Freeze What Works. Build Big.**

ModelHike blends the **creativity of GenAI** with the **precision of structured models**. You’ll start with AI-driven bootstrapping, then progressively lock in stable outputs as templates—all while your code, models, and templates live in Git.

- **Markdown-Inspired DSL**: A simple, structured language to map your domain, like jotting notes on a trail map.
- **AI-Powered Bootstrap & Evolution**: From initial models to evolving features, GenAI stays in your loop and generates models, code, and a live preview—your "basecamp".
- **Intelligent Build Button**: One click locks in what you love and converts it into a reliable template-driven working app.
- **Built for Scale & Flow**: From prototype to mega-app, with instant feedback and zero friction.

---
## 🧰 Key Features

- ✅ **One Build Button** — Works whether AI-generated or template-driven
- 🧠 **GenAI Where You Need It** — Brainstorm freely, structure when ready
- ✍️ **Markdown Models** — Human-readable source of truth
- 🏗️ **Stack-Agnostic** — Generate code for any language or platform
- 📦 **Supports Mega Apps** — Built for systems with complexity and scale



## 💡 Philosophy

> **You shouldn't have to choose between creativity and control.**
>  ModelHike lets you explore freely with GenAI and then lock in what matters—so your app grows naturally from **chaos to clarity**, one accepted file at a time.



## 3. **❤️ Why You’ll Love It**
> _Flow, joy, and developer zen_
>   - ✍️ **Markdown-inspired DSL** — type your domain like prose
>   - 🎢 **Frictionless Feedback** — live previews as you edit
>   - 🤖 **AI in the Loop** — brainstorm, bootstrap, iterate
>   - 🔒 **Freeze & Reuse** — once you love it, lock it into a template
>   - 🌳 **Git-Everything** — diffs, merges, history, peace of mind

## Core Concepts
Imagine each concept as a friendly landmark on your journey:

- ✍️ **Topographic Modeling**
    - Your models live in a **Markdown-inspired DSL**—easy to read, easy to edit.
    - Think of it like drawing contours on a map: you define layers of your system.
    
- 🎢 **Flow State**
    - Instant previews and diffs, whenever you tweak models or prompts
    - No waiting for builds; it’s like the scenery updating as you walk.
    
- 🤖 **AI in the Loop**
   - GenAI helps you bootstrap, brainstorm, and refine—your on-trail companion.
   - You can iterate prompts or models; AI adapts to both.

- 🔒 **Freeze & Reuse**
    - Love a generated file? “Accept” it to turn it into a **deterministic template**.
    - Templates are parameterized by your models—reproducible, versioned and testable.

- 🌲 **Git-Native**
    - All artifacts (models, templates, outputs) are plain-text—diffable, mergeable, and PR-friendly.
    - No black-box platforms, just your familiar Git repo.
    - No opaque platform lock-in—total team collaboration.

- 🏗️ **Mega App Ready**
    - Scale beyond MVPs: multi-service architectures, complex domains, and continuous evolution.
---

## 4. 🔄 Flow Guide (How It Works)
>_Your 5-step joyride_:
>   1. **Prompt** → describe your app
>   2. **Bootstrap** → AI spins up models + code
>   3. **Edit Models** → in our Markdown-inspired DSL
>   4. **Preview & Accept** → one click to freeze into templates
>   5. **Scale & Evolve** → AI + templates dance together, all in Git

Follow these laid-back steps—no sherpas required:

1. **Prompt at Start** 🔍
    - Describe your vision in plain language: `"A booking platform with chat and payments."`
    - ModelHike uses GenAI to **bootstrap**:
        - Initial **domain model** in Markdown-inspired DSL
        - Initial **frontend**, **backend**, and **infra** code
        - Live **preview** of how your system is shaping up

2. **Evolve Your Model** ✍️
    - Edit the **Markdown-inspired DSL** file to refine your domain —like sketching trail notes.
    - Generate diffs and preview updates instantly—like redrawing your trail as you walk.

3. **Iterate with AI** 🔄
    - Tweak prompts or models; GenAI updates code where models are dynamic.
    - Use AI for brainstorming new features or UI prototypes.

4. **Freeze What Works** ✅

    - Click “Accept” to freeze a file into a template—instant consistency.
    - That template now produces the same output every time, driven by your models.

5. **Progressively Transition to Structure** 🚀

    - Some parts of your app remain **dynamic**, GenAI-powered (e.g., experimental features)
    - Others become **stable, predictable**, and powered by templates
    - You control the **transition point** for every output — from exploratory to structured

    This creates a **living build system**—half AI, half compiler—tailored to your design journey.

5. **Climb Higher & Continue** 🚀
    - As you enhance models, AI and templates work together. All changes tracked in Git.
    - Dynamic parts (experimental code) remain GenAI-driven.
    - Stable parts are template-driven—both coexist seamlessly.

---

## 5. 📖 Expedition Paths (Guided Tutorials)

Choose your route to mastery:
_Hands-on, no yawning allowed_

- **Quick Hike**: Bootcamp-style -- Solo bootstrap, basic model edits, and first freeze.
- **Team Trek**: Collaborative DSL modeling, code reviews, and template sharing.
- **Summit Push**: CI/CD integration, multi-service setups, and advanced GenAI tuning.

Each path includes clear steps, interactive code snippets, animated previews and **Pro Tip Waypoints** to keep you joyful and in flow. Like a guided hike, but with code.


---
## 6. 🔍 Compare & Decide (ModelHike vs. Others)

_Why ModelHike > Bolt.new / Lovable.dev / Low-Code_

 - AI-only = fast but fuzzy
 - Low-code = visual but rigid
 - ModelHike = creative + precise + version-controlled

| Feature                            | ModelHike                  | AI-Based Tools   | Low-Code Platforms           |
| ---------------------------------- | -------------------------- | ---------------- | ---------------------------- |
| 🧵 Markdown-inspired DSL            | ✅                          | ❌                | ❌                            |
| 🧠 AI-Generated Project Bootstrap   | ✅                          | ✅                | ❌                            |
| 🧠 Dynamic AI Evolution             | ✅                          | ✅                | ❌                            |
| 🔄 Git Versioning                   | ✅                          | ❌                | ⚠️ Manual / Often Unsupported |
| 🗘️ Visual Flow from Text            | ✅                          | ❌                | ✅ (Template-based)           |
| 🔓 Open Format                      | ✅                          | ❌                | ❌                            |
| 💬 Developer-Centric Language       | ✅                          | ⚠️ (Inconsistent) | ❌                            |
| 🎯 Flexible Precision via Templates | ✅ Automated & model-linked | ❌                | ⚠️ Manual reuse only          |
| 🚀 Fine-Grained Developer Control   | ✅                          | ❌                | ⚠️ Limited                    |
| 🏗️ Scalable for Mega Apps           | ✅ Designed for scale       | ❌ MVP-focused    | ❌ Drag UI limits             |
| 🌄 Joyful Modeling Experience       | ✅ Built for flow           | ⚠️                | ❌                            |

ModelHike isn’t just another AI wrapper or diagram drawer. It’s the **trail system for your architecture journey** — guiding you, not boxing you in.

---

## 7. 🤝 Ranger Station (Community)

- **Trail Markers**: Share your own templates or discover community-built templates.
- **Issue Trailhead**: Report bugs or test features.
- **Group Expeditions**: Join GitHub Discussions for tips and collabs.

## 8. 📍 Ready to Hike?

Feel the flow, spark creativity, enjoy the journey, and build your Mega App—one joyful step at a time. 🚀

- Project Roadmap — *coming soon*
- Contribution Guide — *coming soon*
- Design Philosophy — *coming soon*

We’re building ModelHike to be the most joyful, intuitive, and structured way to model modern software.

See you on the trail. 🏜️