//
//  BlueprintModifier.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

// MARK: - Input type descriptor

/// The expected input type for a blueprint-defined modifier, declared in the `.teso` front matter.
/// Used for runtime type validation before rendering the modifier template.
///
/// Supported values in front matter:  String | Double | Bool | Array | Object | Any
public enum BlueprintModifierInputType: String, Sendable {
    case string = "String"
    case double = "Double"
    case bool = "Bool"
    case array = "Array"
    case object = "Object"
    case any = "Any"

    /// Parses a type name from the front-matter `type:` value.
    /// Falls back to `.any` when the string is nil or unrecognised.
    public init(string typeName: String?) {
        self = .init(rawValue: typeName ?? "") ?? .any
    }

    public func accepts(_ value: Sendable) -> Bool {
        switch self {
        case .string: return value is String
        case .double: return value is Double
        case .bool: return value is Bool
        case .array: return value is [Sendable]
        case .object, .any: return true
        }
    }

    /// The Swift metatype corresponding to this descriptor, used by the type-aware modifier lookup.
    /// `.object` and `.any` map to `Sendable.self` — they accept any value.
    public var metatype: any Any.Type {
        switch self {
        case .string: return String.self
        case .double: return Double.self
        case .bool: return Bool.self
        case .array: return [Sendable].self
        case .object, .any: return (any Sendable).self
        }
    }
}

// MARK: - No-arg blueprint modifier

/// A modifier whose logic is a `.teso` template file in the blueprint's `_modifiers_/` folder.
/// Conforms to both `ModifierWithoutArgsProtocol` (registration) and
/// `ModifierInstanceWithoutArgsProtocol` (execution) — `instance()` returns `self`.
public struct BlueprintModifierWithoutParams: ModifierWithoutArgsProtocol,
    ModifierInstanceWithoutArgsProtocol
{
    public let name: String
    public var inputType: any Any.Type { _blueprintInputType.metatype }
    private let templateSource: TemplateExecutionSource
    private let inputVarName: String
    private let _blueprintInputType: BlueprintModifierInputType
    private let templateSoup: TemplateSoup

    public func instance() -> ModifierInstance { self }

    public func applyTo(value: Sendable, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard _blueprintInputType.accepts(value) else {
            throw TemplateSoup_ParsingError.modifierCalledOnwrongType(
                name, runtimeTypeName(of: value), pInfo)
        }
        return try await templateSoup.renderTemplate(
            source: templateSource,
            data: [inputVarName: value],
            with: pInfo
        )
    }

    public init(
        name: String, templateContents: String, inputVarName: String,
        inputType: BlueprintModifierInputType, templateSoup: TemplateSoup
    ) {
        self.name = name
        self.templateSource = TemplateExecutionSource.parse(
            contents: templateContents,
            identifier: "_modifier_\(name)",
            parseFrontMatter: false
        )
        self.inputVarName = inputVarName
        self._blueprintInputType = inputType
        self.templateSoup = templateSoup
    }
}

// MARK: - With-params blueprint modifier

/// A modifier defined by a `.teso` template file that also accepts positional arguments.
/// Parameter names are declared in the front matter `params:` key (comma-separated).
/// Conforms to both `ModifierWithUnNamedArgsProtocol` (registration) and
/// `ModifierInstanceWithUnNamedArgsProtocol` (execution).
/// `instance()` returns a value-copy; `setArgsGiven` mutates that copy — Swift value
/// semantics ensure each call site gets independent argument state.
public struct BlueprintModifierWithParams: ModifierWithUnNamedArgsProtocol,
    ModifierInstanceWithUnNamedArgsProtocol
{
    public let name: String
    public var inputType: any Any.Type { _blueprintInputType.metatype }
    private let templateSource: TemplateExecutionSource
    private let inputVarName: String
    private let _blueprintInputType: BlueprintModifierInputType
    private let paramNames: [String]
    private let templateSoup: TemplateSoup
    private var arguments: [String] = []

    public func instance() -> ModifierInstance { self }

    public mutating func setArgsGiven(arguments: [String]) {
        self.arguments = arguments
    }

    public func applyTo(value: Sendable, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard _blueprintInputType.accepts(value) else {
            throw TemplateSoup_ParsingError.modifierCalledOnwrongType(
                name, runtimeTypeName(of: value), pInfo)
        }

        var data: StringDictionary = [inputVarName: value]
        for (index, argExpr) in arguments.enumerated() {
            guard index < paramNames.count else { break }
            if let argValue = try await pInfo.ctx.evaluate(expression: argExpr, with: pInfo) {
                data[paramNames[index]] = argValue
            } else {
                throw TemplateSoup_ParsingError.modifierInvalidArguments(name, pInfo)
            }
        }

        return try await templateSoup.renderTemplate(
            source: templateSource,
            data: data,
            with: pInfo
        )
    }

    public init(
        name: String, templateContents: String, inputVarName: String,
        inputType: BlueprintModifierInputType, paramNames: [String], templateSoup: TemplateSoup
    ) {
        self.name = name
        self.templateSource = TemplateExecutionSource.parse(
            contents: templateContents,
            identifier: "_modifier_\(name)",
            parseFrontMatter: false
        )
        self.inputVarName = inputVarName
        self._blueprintInputType = inputType
        self.paramNames = paramNames
        self.templateSoup = templateSoup
    }
}
