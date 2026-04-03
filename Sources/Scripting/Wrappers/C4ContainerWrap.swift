//
//  C4Container_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor C4Container_Wrap : ObjectWrapper {
    public let item: C4Container
    var appModel : AppModel
    
    public var attribs: Attributes { item.attribs }

    public var types : [CodeObject_Wrap] { get async {
        await item.types.compactMap({ CodeObject_Wrap($0)})
    }}
    
    public var apis : [API_Wrap] { get async {
        await item.types.flatMap({
            await $0.getAPIs().snapshot().compactMap({ API_Wrap($0) })
        })
    }}
    
    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = C4ContainerProperty(rawValue: propname) else {
            //nothing found; so check in module attributes
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        let value: Sendable = switch key {
        case .name: await item.name
        case .modules: await item.components(item.components, appModel: appModel)
        case .commons: await item.components(appModel.commonModel, appModel: appModel)
        case .defaultModule: await item.getFirstModule(appModel: appModel)
        
        case .types: await types
        case .hasAnyApis: await apis.count != 0
        case .description: await item.description ?? ""
        case .hasDescription:
            (await item.description).map { !$0.isEmpty } ?? false
        }
        return value
    }

    private func propertyCandidates() async -> [String] {
        let attributes = await item.attribs.attributesList
        let attributeNames = attributes.map { $0.givenKey }
        return C4ContainerProperty.allCases.map(\.rawValue) + attributeNames
    }
    
    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws -> Sendable {
        let attribs = item.attribs
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

    public init(_ item: C4Container, model: AppModel ) {
        self.item = item
        self.appModel = model
    }
}

// MARK: - C4 container property keys (template-facing raw strings)

private enum C4ContainerProperty: String, CaseIterable {
    case name
    case modules
    case commons
    case defaultModule = "default-module"
    case types
    case hasAnyApis = "has-any-apis"
    case description
    case hasDescription = "has-description"
}

