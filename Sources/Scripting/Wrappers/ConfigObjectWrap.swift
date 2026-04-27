//
//  ConfigObjectWrap.swift
//  ModelHike
//

import Foundation

public actor ConfigObject_Wrap: ObjectWrapper {
    public let item: ConfigObject
    public var attribs: Attributes { get async { await item.attribs } }

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = ConfigObjectProperty(rawValue: propname) else {
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        return switch key {
        case .name: await item.name
        case .givenName: await item.givenname
        case .description: await item.description ?? ""
        case .hasDescription: (await item.description).map { $0.isNotEmpty } ?? false
        case .configKind: await item.configKind ?? ""
        case .properties: await item.properties
        case .groups: await item.groups
        }
    }

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws -> Sendable {
        if await item.attribs.has(propname) {
            return await item.attribs[propname]
        }
        throw Suggestions.invalidPropertyInCall(propname, candidates: ConfigObjectProperty.allCases.map(\.rawValue), pInfo: pInfo)
    }

    public var debugDescription: String { get async { await item.debugDescription } }

    public init(_ item: ConfigObject) {
        self.item = item
    }
}

private enum ConfigObjectProperty: String, CaseIterable {
    case name
    case givenName = "given-name"
    case description
    case hasDescription = "has-description"
    case configKind = "config-kind"
    case properties
    case groups
}
