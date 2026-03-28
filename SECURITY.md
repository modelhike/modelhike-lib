# Security Policy

ModelHike takes security seriously. This document explains how to report vulnerabilities and describes the project's security posture.

---

## Supported Versions

| Version | Supported |
|---------|-----------|
| `main`  | Yes       |

ModelHike is pre-release software. Security fixes are applied to the `main` branch.

---

## Reporting a Vulnerability

If you discover a security issue in the ModelHike library, template engine, or generated output:

1. **Do not open a public issue.**
2. Email **security@modelhike.dev** with a detailed description and steps to reproduce.
3. We will acknowledge within **48 hours** and provide a remediation timeline.

Credit will be given in release notes unless you request anonymity.

---

## Security Model

| Layer | Risks Mitigated | Controls |
|-------|-----------------|----------|
| **Template Rendering** | Sandbox escape, injection | TemplateSoup engine with scoped variable isolation (snapshot stack); no `eval` or shell access from templates by default. |
| **File Generation** | Path traversal, overwrite | All file writes confined to the configured output directory. |
| **DSL Parsing** | Malformed input | Structured parsers with explicit grammar; unrecognised lines are silently skipped. |
| **Debug Server** | Network exposure | Debug HTTP/WebSocket server (`DevTester`) binds to localhost only; intended for local development, not production. |

---

## Data Privacy

ModelHike operates **entirely offline**. The core library makes zero network calls. No model data, source code, or generated output is transmitted anywhere.

The `DevTester` debug server is a local-only development tool and should not be exposed to the internet.

---

## Dependencies

The `ModelHike` library target has **zero external dependencies** — reducing supply-chain attack surface to zero for the core library.

The `DevTester` executable depends on SwiftNIO (for the debug HTTP/WebSocket server). This dependency is only used in development tooling, not in the library itself.

---

## Runtime Hardening Recommendations

1. Review generated output before committing — treat it like any code review.
2. Pin your ModelHike version in `Package.swift` to avoid unexpected changes.
3. Run your language-specific security scanners on generated projects (e.g., `npm audit`, `govulncheck`).

---

## Contact

Email: **security@modelhike.dev**
