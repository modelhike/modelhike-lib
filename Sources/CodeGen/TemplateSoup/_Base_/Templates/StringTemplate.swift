//
//  StringTemplate.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public struct StringTemplate: Template, Script, ExpressibleByStringLiteral,
    ExpressibleByStringInterpolation
{
    public var name: String = "string"

    let items: [StringConvertible]

    @discardableResult
    static func append(_ obj: StringTemplate, with item: StringConvertible) -> Self {
        var newItems = obj.items
        newItems.append(item)
        return StringTemplate(contentsOf: newItems)
    }

    public func toString() -> String {
        items.map { $0.toString() }.joined()
    }

    /// Render all leaf strings joined by `separator`.
    ///
    /// Nested `StringTemplate` items are flattened recursively so that every
    /// level of the tree uses the same separator. An empty string `""` in any
    /// template acts as a blank-line sentinel: when joined with `"\n"` it
    /// becomes a blank line in the output, exactly like an empty line in
    /// hand-written Swift.
    public func toString(separator: String) -> String {
        flatten().joined(separator: separator)
    }

    /// Recursively collect every leaf string from this template and all nested
    /// `StringTemplate` items. Non-StringTemplate `StringConvertible` values
    /// are emitted as single strings via their own `toString()`.
    public func flatten() -> [String] {
        items.flatMap { item -> [String] in
            if let nested = item as? StringTemplate {
                return nested.flatten()
            }
            return [item.toString()]
        }
    }

    public var string: String { toString() }

    public init(@StringConvertibleBuilder _ builder: () async -> [StringConvertible]) async {
        items = await builder()
    }

    public init(@StringConvertibleBuilder _ builder: () -> [StringConvertible]) {
        items = builder()
    }

    public init(stringLiteral value: String) {
        items = [value]
    }

    public init(stringInterpolation: String) {
        items = [stringInterpolation]
    }

    public init(_ value: String) {
        items = [value]
    }

    public init(contentsOf value: [StringConvertible]) {
        items = value
    }

    public init(contents: String, name: String) {
        self.items = [contents]
        self.name = name
    }

    static func + (lhs: StringTemplate, rhs: any StringConvertible) -> StringTemplate {
        return StringTemplate.append(lhs, with: rhs)
    }

    static func + (lhs: any StringConvertible, rhs: StringTemplate) -> StringTemplate {
        return StringTemplate.append(rhs, with: lhs)

    }
}

public struct TabChar: StringConvertible {
    let linesCount: Int
    static public let characters = "\t"

    public func toString() -> String {
        String(repeating: Self.characters, count: linesCount)
    }

    public init(_ lines: Int) {
        self.linesCount = lines
    }

    public init() {
        self.linesCount = 1
    }
}

extension String {
    public static func += (lhs: inout StringTemplate, rhs: String) -> StringTemplate {
        return StringTemplate.append(lhs, with: rhs)
    }

    public static func += (lhs: inout String, rhs: StringTemplate) -> StringTemplate {
        return StringTemplate.append(rhs, with: lhs)
    }
}
