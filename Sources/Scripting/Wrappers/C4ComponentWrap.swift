//
//  C4Component_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor C4Component_Wrap : ObjectWrapper {
    public let item: C4Component
    let model : AppModel
    
    public var attribs: Attributes { item.attribs }

    public var types: [CodeObject_Wrap] { get async {
        await item.types.compactMap({ CodeObject_Wrap($0)})
    }}
    
    public var embeddedTypes: [CodeObject_Wrap] { get async {
        await item.types.compactMap({
            if await $0.dataType == .embeddedType {CodeObject_Wrap($0)} else {nil}})
    }}
    
    public var entities: [CodeObject_Wrap] { get async {
        await item.types.compactMap({
            if await $0.dataType == .entity {CodeObject_Wrap($0)} else {nil}})
    }}
    
    public var dtos: [CodeObject_Wrap] { get async {
        await item.types.compactMap({
            if await $0.dataType == .dto, let dto = $0 as? DtoObject {CodeObject_Wrap(dto)} else {nil}})
    }}
    
    public var entitiesAndDtos : [CodeObject_Wrap] { get async {
        var list = await entities
        await list.append(contentsOf: dtos)
        return list
    }}
    
    public var apis: [API_Wrap] {
        get async {
            var result: [API_Wrap] = []
            
            for type in await item.types {
                let apis = await type.getAPIs().snapshot()
                let converted = await apis.compactMap { API_Wrap($0) }
                result.append(contentsOf: converted)
            }
            
            return result
        }
    }
    
    public var pushDataApis : [API_Wrap] { get async {
        await self.apis.compactMap({
            let itemtype = await $0.item.type
            
            if (itemtype == .pushData ||
                itemtype == .pushDataList
            ) { return $0 } else {return nil}    })
    }}
    
    public var mutationApis : [API_Wrap] { get async {
        await self.apis.compactMap({
            let itemtype = await $0.item.type
            
            if (itemtype == .create ||
                itemtype == .update ||
                itemtype == .delete ||
                itemtype == .mutationUsingCustomLogic
            ) { return $0 } else {return nil}
        })
    }}
    
    public var queryApis : [API_Wrap] { get async {
        await self.apis.compactMap({
            let itemtype = await $0.item.type

            if (itemtype == .getById ||
                itemtype == .getByCustomProperties ||
                itemtype == .list ||
                itemtype == .listByCustomProperties
            ) { return $0 } else {return nil}    })
    }}
    
    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = C4ComponentProperty(rawValue: propname) else {
            //nothing found; so check in module attributes
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        let value: Sendable = switch key {
        case .name: await item.name
        case .types: await types
        case .embeddedTypes: await embeddedTypes
        case .hasEmbeddedTypes: await embeddedTypes.count != 0
        case .entities: await entities
        case .hasEntities: await entities.count != 0
        case .dtos: await dtos
        case .hasDtos: await dtos.count != 0
        case .entitiesAndDtos: await entitiesAndDtos
        case .pushApis: await pushDataApis
        case .hasPushApis: await pushDataApis.count != 0
        case .queryApis: await queryApis
        case .hasQueryApis: await queryApis.count != 0
        case .mutationApis: await mutationApis
        case .hasMutationApis: await mutationApis.count != 0
        case .hasAnyApis: await apis.count != 0
        case .description: await item.description ?? ""
        case .hasDescription:
            (await item.description).map { !$0.isEmpty } ?? false
        case .expressions:
            await item.expressions.map { TypeProperty_Wrap($0) }
        case .hasExpressions: await !item.expressions.isEmpty
        case .functions:
            await item.functions.map { MethodObject_Wrap($0) }
        case .hasFunctions: await !item.functions.isEmpty
        case .namedConstraints:
            await item.namedConstraints.snapshot().map { Constraint_Wrap($0) }
        case .hasNamedConstraints: await !item.namedConstraints.snapshot().isEmpty
        }
        return value
    }

    private func propertyCandidates() async -> [String] {
        let attributes = await item.attribs.attributesList
        let attributeNames = attributes.map { $0.givenKey }
        return C4ComponentProperty.allCases.map(\.rawValue) + attributeNames
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
    
    public var debugDescription: String { get async {
        await item.debugDescription
    }}

    public init(_ item: C4Component, model: AppModel ) {
        self.item = item
        self.model = model
    }
}

// MARK: - C4 component property keys (template-facing raw strings)

private enum C4ComponentProperty: String, CaseIterable {
    case name
    case types
    case embeddedTypes = "embedded-types"
    case hasEmbeddedTypes = "has-embedded-types"
    case entities
    case hasEntities = "has-entities"
    case dtos
    case hasDtos = "has-dtos"
    case entitiesAndDtos = "entities-and-dtos"
    case pushApis = "push-apis"
    case hasPushApis = "has-push-apis"
    case queryApis = "query-apis"
    case hasQueryApis = "has-query-apis"
    case mutationApis = "mutation-apis"
    case hasMutationApis = "has-mutation-apis"
    case hasAnyApis = "has-any-apis"
    case description
    case hasDescription = "has-description"
    case expressions
    case hasExpressions = "has-expressions"
    case functions
    case hasFunctions = "has-functions"
    case namedConstraints = "named-constraints"
    case hasNamedConstraints = "has-named-constraints"
}




