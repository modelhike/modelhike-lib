//
//  C4Container_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor C4Container_Wrap : ObjectWrapper {
    public let item: C4Container
    var appModel : AppModel

    private var _cachedTypes: [CodeObject_Wrap]?
    private var _cachedApis: [API_Wrap]?

    public var attribs: Attributes { item.attribs }

    public var types: [CodeObject_Wrap] {
        get async {
            if let cached = _cachedTypes { return cached }
            let computed = await item.types.map { CodeObject_Wrap($0) }
            _cachedTypes = computed
            return computed
        }
    }

    public var apis: [API_Wrap] {
        get async {
            if let cached = _cachedApis { return cached }
            var result: [API_Wrap] = []
            for t in await item.types {
                result.append(contentsOf: (await t.getAPIs().snapshot()).map(API_Wrap.init))
            }
            _cachedApis = result
            return result
        }
    }
    
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
        case .hasAnyApis: (await apis).isNotEmpty
        case .description: await item.description ?? ""
        case .hasDescription:
            (await item.description).map { $0.isNotEmpty } ?? false
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

