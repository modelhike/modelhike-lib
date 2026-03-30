//
//  ModifierInstance.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public struct ModifierInstanceWithoutArgs<I, T: Sendable> : ModifierInstanceWithoutArgsProtocol {
    public let name : String
    public var inputType: any Any.Type { _callerType }
    private let _callerType: I.Type
    private let handler: @Sendable (I, ParsedInfo) async throws  -> T?
    
    public func applyTo(value : Sendable, with pInfo: ParsedInfo) async throws -> Sendable? {
        // Two-part check:
        // 1. `as? I` — verifies the value is compatible with the registered input type.
        // 2. `type(of:) == _callerType` — enforces an exact concrete-type match, preventing
        //    e.g. a Double from being silently widened to Sendable and accepted by a String modifier.
        //    Skipped when _callerType is `(any Sendable).self`, meaning the modifier intentionally
        //    accepts any value (e.g. `typename`, `sample-json`).
        guard let typedValue = value as? I,
              _callerType == (any Sendable).self || type(of: value) == _callerType else {
            throw TemplateSoup_ParsingError.modifierCalledOnwrongType(self.name, runtimeTypeName(of: value), pInfo)
        }
        return try await handler(typedValue, pInfo)
    }
    
    public init(name: String, handler: @escaping @Sendable (I, ParsedInfo) async throws -> T?) {
        self.name = name
        self._callerType = I.self
        self.handler = handler
    }
}

public struct ModifierInstanceWithUnNamedArgs<I, T: Sendable> : ModifierInstanceWithUnNamedArgsProtocol {
    public var name : String
    public var inputType: any Any.Type { _callerType }
    private let _callerType: I.Type
    private let handler: @Sendable (I, [Sendable], ParsedInfo) async throws -> T?
    private var arguments: [String] = []
    
    public mutating func setArgsGiven(arguments: [String]) {
        self.arguments = arguments
    }
    
    public func applyTo(value : Sendable, with pInfo: ParsedInfo) async throws -> Sendable? {
        // Two-part check (identical reasoning to ModifierInstanceWithoutArgs):
        // 1. `as? I` — verifies the value is compatible with the registered input type.
        // 2. `type(of:) == _callerType` — enforces an exact concrete-type match, preventing
        //    e.g. a Double from being silently widened to Sendable and accepted by a String modifier.
        //    Skipped when _callerType is `(any Sendable).self`, meaning the modifier intentionally
        //    accepts any value (e.g. `typename`, `sample-json`).
        guard let typedValue = value as? I,
              _callerType == (any Sendable).self || type(of: value) == _callerType else {
            throw TemplateSoup_ParsingError.modifierCalledOnwrongType(self.name, runtimeTypeName(of: value), pInfo)
        }
        var argumentValues: [Sendable] = []
        for argument in arguments {
            if let argValue = try await pInfo.ctx.evaluate(expression: argument, with: pInfo) {
                argumentValues.append(argValue)
            } else {
                throw TemplateSoup_ParsingError.modifierInvalidArguments(self.name, pInfo)
            }
        }
        return try await handler(typedValue, argumentValues, pInfo)
    }
    
    public init(name: String, handler: @escaping @Sendable (I, [Sendable], ParsedInfo) async throws -> T?) {
        self.name = name
        self._callerType = I.self
        self.handler = handler
    }
}

public protocol ModifierInstanceWithoutArgsProtocol : ModifierInstance {
}

public protocol ModifierInstanceWithUnNamedArgsProtocol : ModifierInstanceWithArgsProtocol {
    mutating func setArgsGiven(arguments: [String])
}

public protocol ModifierInstanceWithArgsProtocol : ModifierInstance {
}

public protocol ModifierInstance: Sendable {
    var name : String {get}
    var inputType: any Any.Type { get }
    func applyTo(value : Sendable, with pInfo: ParsedInfo) async throws -> Sendable?
}
