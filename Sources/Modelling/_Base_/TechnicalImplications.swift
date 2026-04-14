//
//  TechnicalImplications.swift
//  ModelHike
//

import Foundation

/// A single `[ … ]` technical-review note from the DSL (content inside the brackets).
public struct TechnicalImplication: Sendable, Hashable {
    public let text: String

    public init(_ text: String) {
        self.text = text.trim()
    }
}

/// Value types (e.g. ``ParameterMetadata``, ``VirtualGroup``) that store parsed `[ … ]` notes as an array.
/// Actors use ``HasTechnicalImplications_Actor`` with ``TechnicalImplications`` instead.
public protocol HasTechnicalImplicationsValues: Sendable {
    var technicalImplications: [TechnicalImplication] { get }
}

/// Model elements that carry `[ … ]` technical-review notes (parsed after `(attributes)`).
public protocol HasTechnicalImplications_Actor: Actor {
    var technicalImplications: TechnicalImplications { get }
}

/// Bracket markers on DSL lines: `[ note ]` after `(attributes)` and before `#hash-tags`.
/// Intended for technical-review notes; non-technical readers can ignore them.
public actor TechnicalImplications {
    private var values: [TechnicalImplication] = []

    public init() {}

    public func append(_ item: TechnicalImplication) {
        guard item.text.isNotEmpty else { return }
        values.append(item)
    }

    public func appendAll(_ items: [TechnicalImplication]) {
        for item in items {
            append(item)
        }
    }

    public func all() -> [TechnicalImplication] {
        values
    }

    public var isEmpty: Bool {
        values.isEmpty
    }
}
