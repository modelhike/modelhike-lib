//
//  AgentObjectWrap.swift
//  ModelHike
//

import Foundation

public actor AgentObject_Wrap: ObjectWrapper {
    public let item: AgentObject
    public var attribs: Attributes { get async { await item.attribs } }

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = AgentObjectProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(propname, candidates: AgentObjectProperty.allCases.map(\.rawValue), pInfo: pInfo)
        }
        return switch key {
        case .name: await item.name
        case .givenName: await item.givenname
        case .kind: await item.componentKind.rawValue
        case .description: await item.description ?? ""
        case .hasDescription: (await item.description).map { $0.isNotEmpty } ?? false
        case .prompts: await item.prompts
        case .hasPrompts: await item.prompts.isNotEmpty
        case .tools: await item.tools
        case .hasTools: await item.tools.isNotEmpty
        case .sections: await item.sections
        case .slashCommands: await item.slashCommands
        case .guardrails: await item.guardrails
        }
    }

    public var debugDescription: String { get async { await item.debugDescription } }

    public init(_ item: AgentObject) {
        self.item = item
    }
}

private enum AgentObjectProperty: String, CaseIterable {
    case name
    case givenName = "given-name"
    case kind
    case description
    case hasDescription = "has-description"
    case prompts
    case hasPrompts = "has-prompts"
    case tools
    case hasTools = "has-tools"
    case sections
    case slashCommands = "slash-commands"
    case guardrails
}
