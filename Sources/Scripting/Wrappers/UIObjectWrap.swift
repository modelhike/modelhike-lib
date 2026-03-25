//
//  UIObject_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor UIObject_Wrap: ObjectWrapper {
    public let item: UIObject

    public var attribs: Attributes { get async { await item.attribs }}

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {

        let value: Sendable =
            switch propname {
            case "name": await item.name
            case "given-name": await item.givenname
            default:
                //nothing found; so check in module attributes
                try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
            }

        return value
    }

    private func propertyCandidates() async -> [String] {
        let attributes = await item.attribs.attributesList
        let attributeNames = attributes.map { $0.givenKey }
        return ["name", "given-name"] + attributeNames
    }

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws -> Sendable {
        let attribs = await item.attribs
        if await attribs.has(propname) {
            return await attribs[propname]
        } else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: await propertyCandidates(),
                pInfo: pInfo
            )
        }
    }
    
    public var debugDescription: String { get async { await item.debugDescription }}

    public init(_ item: UIObject) {
        self.item = item
    }
}
