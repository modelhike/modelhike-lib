//
//  MethodObjectWrap.swift
//  ModelHike
//

import Foundation

public actor MethodObject_Wrap: ObjectWrapper {
    public let item: MethodObject

    public var attribs: Attributes { get async { await item.attribs }}

    private static let basePropertyCandidates: [String] = [
        "name", "given-name", "return-type", "has-return-type",
        "parameters", "has-parameters", "has-logic", "logic-lines",
    ]

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        switch propname {
        case "name": return await item.name
        case "given-name": return await item.givenname
        case "return-type": return await item.returnType
        case "has-return-type": return await item.returnType.kind != .unKnown
        case "parameters":
            return await item.parameters.map { MethodParameter_Wrap($0) }
        case "has-parameters": return !(await item.parameters.isEmpty)
        case "has-logic": return await item.hasLogic
        case "logic-lines":
            guard let logic = await item.logic, !logic.isEmpty else {
                return [FlatLogicLine_Wrap]()
            }
            let lines = await FlatLogicLineData.flatten(logic: logic)
            return lines.map { FlatLogicLine_Wrap($0) }
        default:
            if await item.attribs.has(propname) {
                return await item.attribs[propname]
            }
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: await propertyCandidates(),
                pInfo: pInfo
            )
        }
    }

    private func propertyCandidates() async -> [String] {
        let attrs = await item.attribs.attributesList
        let attributeNames = attrs.map { $0.givenKey }
        return Self.basePropertyCandidates + attributeNames
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

    private static let propertyCandidates: [String] = [
        "name", "type", "is-array", "is-required", "has-default-value", "default-value",
    ]

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        let value: Sendable =
            switch propname {
            case "name": item.name
            case "type": item.type
            case "is-array": item.type.isArray
            case "is-required": item.metadata.required == .yes
            case "has-default-value": item.metadata.defaultValue != nil
            case "default-value": item.metadata.defaultValue ?? ""
            default:
                throw Suggestions.invalidPropertyInCall(
                    propname,
                    candidates: Self.propertyCandidates,
                    pInfo: pInfo
                )
            }
        return value
    }

    public var debugDescription: String {
        "param: \(item.name)"
    }

    public init(_ item: MethodParameter) {
        self.item = item
    }
}
