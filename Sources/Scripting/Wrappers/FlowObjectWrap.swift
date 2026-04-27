//
//  FlowObjectWrap.swift
//  ModelHike
//

import Foundation

public actor FlowObject_Wrap: ObjectWrapper {
    public let item: FlowObject
    public var attribs: Attributes { get async { await item.attribs } }

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = FlowObjectProperty(rawValue: propname) else {
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        return switch key {
        case .name: await item.name
        case .givenName: await item.givenname
        case .kind: String(describing: await item.dataType)
        case .mode: await item.mode.rawValue
        case .description: await item.description ?? ""
        case .hasDescription: (await item.description).map { $0.isNotEmpty } ?? false
        case .states: await item.states
        case .transitions: await item.transitions
        case .participants: await item.participants
        case .messages: await item.messages
        case .waits: await item.waits
        case .calls: await item.calls
        case .steps: await item.steps
        case .branches: await item.branches
        case .returns: await item.returns
        }
    }

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws -> Sendable {
        if await item.attribs.has(propname) {
            return await item.attribs[propname]
        }
        throw Suggestions.invalidPropertyInCall(propname, candidates: FlowObjectProperty.allCases.map(\.rawValue), pInfo: pInfo)
    }

    public var debugDescription: String { get async { await item.debugDescription } }

    public init(_ item: FlowObject) {
        self.item = item
    }
}

private enum FlowObjectProperty: String, CaseIterable {
    case name
    case givenName = "given-name"
    case kind
    case mode = "flow-mode"
    case description
    case hasDescription = "has-description"
    case states
    case transitions
    case participants
    case messages
    case waits
    case calls
    case steps
    case branches
    case returns
}
