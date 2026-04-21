//
//  C4Component_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor C4Component_Wrap : ObjectWrapper {
    public let item: C4Component
    let model : AppModel

    private var _cachedTypes: [CodeObject_Wrap]?
    private var _cachedApis: [API_Wrap]?
    private var _cachedEmbeddedTypes: [CodeObject_Wrap]?
    private var _cachedEntities: [CodeObject_Wrap]?
    private var _cachedDtos: [CodeObject_Wrap]?
    private var _cachedServices: [CodeObject_Wrap]?

    public var attribs: Attributes { item.attribs }

    public var types: [CodeObject_Wrap] {
        get async {
            if let cached = _cachedTypes { return cached }
            let computed = await item.types.map { CodeObject_Wrap($0) }
            _cachedTypes = computed
            return computed
        }
    }

    public var embeddedTypes: [CodeObject_Wrap] {
        get async {
            if let cached = _cachedEmbeddedTypes { return cached }
            let out = await typesFiltered { await $0.dataType == .embeddedType }
            _cachedEmbeddedTypes = out
            return out
        }
    }

    public var entities: [CodeObject_Wrap] {
        get async {
            if let cached = _cachedEntities { return cached }
            let out = await typesFiltered { await $0.dataType == .entity }

            _cachedEntities = out
            return out
        }
    }

    public var dtos: [CodeObject_Wrap] {
        get async {
            if let cached = _cachedDtos { return cached }
            let out = await typesFiltered { o in
                await o.dataType == .dto && o is DtoObject
            }
            _cachedDtos = out
            return out
        }
    }

    public var services: [CodeObject_Wrap] {
        get async {
            if let cached = _cachedServices { return cached }
            let out = await typesFiltered { await $0.dataType == .service }
            _cachedServices = out
            return out
        }
    }

    public var entitiesAndDtos: [CodeObject_Wrap] {
        get async {
            var list = await entities
            await list.append(contentsOf: dtos)
            return list
        }
    }

    public var apis: [API_Wrap] {
        get async {
            if let cached = _cachedApis { return cached }
            var result: [API_Wrap] = []
            // component-level direct APIs (from its own # apis section)
            for a in await item.getAPIs().snapshot() {
                result.append(API_Wrap(a))
            }
            // APIs declared on each child type
            for wrapped in await types {
                let apis = await wrapped.item.getAPIs().snapshot()
                for a in apis {
                    result.append(API_Wrap(a))
                }
            }
            _cachedApis = result
            return result
        }
    }

    public var pushDataApis: [API_Wrap] {
        get async { await apisFiltered(by: Self.isPushApiType) }
    }

    public var mutationApis: [API_Wrap] {
        get async { await apisFiltered(by: Self.isMutationApiType) }
    }

    public var queryApis: [API_Wrap] {
        get async { await apisFiltered(by: Self.isQueryApiType) }
    }

    /// `compactMap` / `filter` cannot `await` per element; this is the same O(n) single pass.
    private func apisFiltered(by predicate: (APIType) -> Bool) async -> [API_Wrap] {
        var out: [API_Wrap] = []
        for w in await apis {
            if predicate(await w.item.type) { out.append(w) }
        }
        return out
    }

    private static func isPushApiType(_ t: APIType) -> Bool {
        t == .pushData || t == .pushDataList
    }

    private static func isMutationApiType(_ t: APIType) -> Bool {
        t == .create || t == .update || t == .delete || t == .mutationUsingCustomLogic
    }

    private static func isQueryApiType(_ t: APIType) -> Bool {
        t == .getById || t == .getByCustomProperties || t == .list || t == .listByCustomProperties
    }

    private func hasPushDataApi() async -> Bool {
        for w in await apis {
            if Self.isPushApiType(await w.item.type) { return true }
        }
        return false
    }

    private func hasMutationApi() async -> Bool {
        for w in await apis {
            if Self.isMutationApiType(await w.item.type) { return true }
        }
        return false
    }

    private func hasQueryApi() async -> Bool {
        for w in await apis {
            if Self.isQueryApiType(await w.item.type) { return true }
        }
        return false
    }
    
    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = C4ComponentProperty(rawValue: propname) else {
            //nothing found; so check in module attributes
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        let value: Sendable = switch key {
        case .name: await item.name
        case .types: await types
        case .embeddedTypes: await embeddedTypes
        case .hasEmbeddedTypes: (await embeddedTypes).isNotEmpty
        case .entities: await entities
        case .hasEntities: (await entities).isNotEmpty
        case .services: await services
        case .hasServices: (await services).isNotEmpty
        case .dtos: await dtos
        case .hasDtos: (await dtos).isNotEmpty
        case .entitiesAndDtos: await entitiesAndDtos
        case .pushApis: await pushDataApis
        case .hasPushApis: await hasPushDataApi()
        case .queryApis: await queryApis
        case .hasQueryApis: await hasQueryApi()
        case .mutationApis: await mutationApis
        case .hasMutationApis: await hasMutationApi()
        case .hasAnyApis: (await apis).isNotEmpty
        case .description: await item.description ?? ""
        case .hasDescription:
            (await item.description).map { $0.isNotEmpty } ?? false
        case .expressions:
            await item.expressions.map { TypeProperty_Wrap($0) }
        case .hasExpressions: await item.expressions.isNotEmpty
        case .functions:
            await item.functions.map { MethodObject_Wrap($0) }
        case .hasFunctions: await item.functions.isNotEmpty
        case .namedConstraints:
            await item.namedConstraints.snapshot().map { Constraint_Wrap($0) }
        case .hasNamedConstraints: await item.namedConstraints.snapshot().isNotEmpty
        }
        return value
    }

    /// Filters `item.types` and wraps each match as ``CodeObject_Wrap`` (same end result as filtering ``types``).
    private func typesFiltered(by predicate: (CodeObject) async -> Bool) async -> [CodeObject_Wrap] {
        var out: [CodeObject_Wrap] = []
        for o in await item.types {
            if await predicate(o) { out.append(CodeObject_Wrap(o)) }
        }
        return out
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
    case services
    case hasServices = "has-services"
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




