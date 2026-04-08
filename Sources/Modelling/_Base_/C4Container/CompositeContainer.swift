//
//  CompositeContainer.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

/// A lightweight marker wrapping a ``C4Container`` that represents a **monorepo** or
/// multi-service deployment unit.
///
/// ## Purpose — Monorepo code generation
/// A composite container maps to a **monorepo** layout where all modules live together in one
/// generated project (e.g. a NestJS or Spring Boot monorepo with a shared workspace root,
/// per-package subdirectories, and cross-cutting config files).
///
/// The pipeline passes the **whole container** to the blueprint unchanged — as `@composite-container` —
/// so the blueprint receives all modules at once and can decide the full output structure itself.
/// This is intentional: a monorepo is not simply "one blueprint run per module"; it requires
/// shared root files (workspace config, Docker setup, etc.) alongside per-module packages, and
/// only the blueprint knows how to arrange them.
///
/// The sandbox injects the container under a different template variable name depending on type:
/// - Leaf containers → **`@container`**
/// - Composite containers → **`@composite-container`**
///
/// ## DSL declaration
/// Mark a container as composite by adding `(composite-container)` or `(microservices)` on the
/// container fence line in the `.modelhike` file:
/// ```
/// === Services (microservices) #blueprint(api-nestjs-monorepo) ===
/// + UserModule
/// + OrderModule
/// === ===
/// ```
/// Both attributes are equivalent — they signal "this container is a monorepo unit".
///
public struct CompositeContainer: Sendable {
    public let container: C4Container

    public init(container: C4Container) {
        self.container = container
    }

    /// Returns `true` when the container is declared with `(container-group)` or `(microservices)`,
    /// indicating it is a monorepo unit. The blueprint receives the full container and decides output structure.
    public static func isCompositeContainer(_ container: C4Container) async -> Bool {
        let isGroup = await container.attribs.has("composite-container")
        let isMs = await container.attribs.has("microservices")
        return isGroup || isMs
    }
}
