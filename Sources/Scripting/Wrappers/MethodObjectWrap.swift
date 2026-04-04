//
//  MethodObjectWrap.swift
//  ModelHike
//

import Foundation

public actor MethodObject_Wrap: ObjectWrapper {
    public let item: MethodObject

    public var attribs: Attributes { get async { await item.attribs }}

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = MethodObjectProperty(rawValue: propname) else {
            if await item.attribs.has(propname) {
                return await item.attribs[propname]
            }
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: await propertyCandidates(),
                pInfo: pInfo
            )
        }
        switch key {
        case .name: return await item.name
        case .givenName: return await item.givenname
        case .returnType: return await item.returnType
        case .hasReturnType: return await item.returnType.kind != .unKnown
        case .parameters:
            return await item.parameters.map { MethodParameter_Wrap($0) }
        case .hasParameters: return (await item.parameters).isNotEmpty
        case .hasLogic: return await item.hasLogic
        case .logicLines:
            guard let logic = await item.logic, logic.isNotEmpty else {
                return [FlatLogicLine_Wrap]()
            }
            let lines = await FlatLogicLineData.flatten(logic: logic)
            return lines.map { FlatLogicLine_Wrap($0) }
        case .hasDbLogic:
            guard let logic = await item.logic, logic.isNotEmpty else { return false }
            return await logic.containsDataAccessStatement()
        case .hasDbTxnLogic:
            guard let logic = await item.logic, logic.isNotEmpty else { return false }
            return await logic.containsTransactionControlStatement()
        case .hasHttpLogic:
            guard let logic = await item.logic, logic.isNotEmpty else { return false }
            return await logic.containsHttpClientStatement()
        case .hasWsLogic:
            guard let logic = await item.logic, logic.isNotEmpty else { return false }
            return await logic.containsWebSocketStatement()
        case .hasGrpcLogic:
            guard let logic = await item.logic, logic.isNotEmpty else { return false }
            return await logic.containsGrpcClientStatement()
        case .description: return await item.description ?? ""
        case .hasDescription:
            return (await item.description).map { $0.isNotEmpty } ?? false
        }
    }

    private func propertyCandidates() async -> [String] {
        let attrs = await item.attribs.attributesList
        let attributeNames = attrs.map { $0.givenKey }
        return MethodObjectProperty.allCases.map(\.rawValue) + attributeNames
    }

    public var debugDescription: String {
        get async { "method: \(await item.name)" }
    }

    public init(_ item: MethodObject) {
        self.item = item
    }
}

public actor MethodParameter_Wrap: DynamicMemberLookup, SendableDebugStringConvertible {
    private let item: MethodParameter

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = MethodParameterProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: MethodParameterProperty.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return switch key {
        case .name: item.name
        case .type: item.type
        case .isArray: item.type.isArray
        case .isRequired: item.metadata.required == .yes
        case .hasDefaultValue: item.metadata.defaultValue != nil
        case .defaultValue: item.metadata.defaultValue ?? ""
        case .isOutput: item.metadata.isOutput
        case .isInout: item.metadata.isOutput && item.metadata.required == .yes
        case .description: item.metadata.description ?? ""
        case .hasDescription: item.metadata.description.map { $0.isNotEmpty } ?? false
        }
    }

    public var debugDescription: String {
        "param: \(item.name)"
    }

    public init(_ item: MethodParameter) {
        self.item = item
    }
}

// MARK: - Method / parameter property keys (template-facing raw strings)

private enum MethodObjectProperty: String, CaseIterable {
    case name
    case givenName = "given-name"
    case returnType = "return-type"
    case hasReturnType = "has-return-type"
    case parameters
    case hasParameters = "has-parameters"
    case hasLogic = "has-logic"
    case logicLines = "logic-lines"
    case hasDbLogic = "has-db-logic"
    case hasDbTxnLogic = "has-db-txn-logic"
    case hasHttpLogic = "has-http-logic"
    case hasWsLogic = "has-ws-logic"
    case hasGrpcLogic = "has-grpc-logic"
    case description
    case hasDescription = "has-description"
}

private enum MethodParameterProperty: String, CaseIterable {
    case name
    case type
    case isArray = "is-array"
    case isRequired = "is-required"
    case hasDefaultValue = "has-default-value"
    case defaultValue = "default-value"
    case isOutput = "is-output"
    case isInout = "is-inout"
    case description
    case hasDescription = "has-description"
}
