//
//  API_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor API_Wrap : ObjectWrapper {
    public let item: API
    
    public var attribs: Attributes { get async { await item.attribs }}
    
    public var queryParams:  [APIParam_Wrap] { get async {
        await item.queryParams.compactMap({ APIParam_Wrap($0) })
    }}
    
    public var customProperties : [TypeProperty_Wrap] { get async {
        if let custom = item as? APIWithCustomProperties {
            await custom.properties.compactMap({ TypeProperty_Wrap($0) })
        } else {
            []
        }
    }}
    
    public var customProperties_and_condition : Bool { get async {
        if let custom = item as? APIWithCustomProperties {
            await custom.andCondition
        } else {
            false
        }
    }}
    
    public var customParameters : [APICustomParameter_Wrap] { get async {
        if let custom = item as? CustomLogicAPI {
            await custom.parameters.compactMap({ APICustomParameter_Wrap($0) })
        } else {
            []
        }
    }}
    
    public var returnType : Sendable { get async {
        if let custom = item as? CustomLogicAPI {
            await custom.returnType
        } else {
            await item.entity.name
        }
    }}
    
    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = APIProperty(rawValue: propname) else {
            //nothing found; so check in attributes
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        return try await value(for: key, pInfo: pInfo)
    }

    private func value(for property: APIProperty, pInfo: ParsedInfo) async throws -> Sendable {
        switch property {
        case .entity: await CodeObject_Wrap(item.entity)
        case .returnType: try await CheckSendable(value: returnType, pInfo: pInfo)
        case .inputType: await item.entity.name
        case .hasPath: await item.path.isNotEmpty
        case .path: await item.path
        case .name: await item.name
        case .type: await item.type

        case .givenname: await item.givenname
        case .baseUrl: await item.baseUrl
        case .version: await item.version
        case .queryParams: await queryParams

        case .isCreate: await item.type == .create
        case .isUpdate: await item.type == .update
        case .isDelete: await item.type == .delete
        case .isGetById: await item.type == .getById
        case .isGetByCustomProps: await item.type == .getByCustomProperties
        case .isList: await item.type == .list
        case .isListByCustomProps: await item.type == .listByCustomProperties
        case .isPushData: await item.type == .pushData
        case .isPushDatalist: await item.type == .pushDataList
        case .isGetByCustomLogic: await item.type == .getByUsingCustomLogic
        case .isListByCustomLogic: await item.type == .listByUsingCustomLogic
        case .isMutationByCustomLogic: await item.type == .mutationUsingCustomLogic
        
        case .propertiesInvolved: await customProperties
        case .isAndConditionForPropertiesInvolved: await customProperties_and_condition
        case .customParams: await customParameters
        }
    }

    private func propertyCandidates() async -> [String] {
        let attributes = await item.attribs.attributesList
        let attributeNames = attributes.map { $0.givenKey }
        return APIProperty.allCases.map(\.rawValue) + attributeNames
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
    
    public var debugDescription: String { get async {
        await item.debugDescription
    }}
    
    public init(_ item: API) {
        self.item = item
    }
}

public actor APIParam_Wrap : DynamicMemberLookup, Sendable {
    public let item: APIQueryParamWrapper
    
    public func getValueOf(property propname: String, with pInfo: ParsedInfo) throws -> Sendable? {
        guard let key = APIParamProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: APIParamProperty.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return switch key {
        case .propMappingFirst: item.propMaping.first
        case .paramName: item.queryParam.name
        case .hasSecondParamName: item.queryParam.hasSecondParamName
        case .secondParamName: item.queryParam.SecondName
        case .hasMultipleParams: item.queryParam.canHaveMultipleValues
        }
    }
    
    public init(_ item: APIQueryParamWrapper) {
        self.item = item
    }
}

public actor APICustomParameter_Wrap : DynamicMemberLookup, Sendable {
    public let item: MethodParameter
    
    public func getValueOf(property propname: String, with pInfo: ParsedInfo) throws -> Sendable? {
        guard let key = APICustomParameterProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: APICustomParameterProperty.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return switch key {
        case .name: item.name
        case .type: item.type
        case .isArray: item.type.isArray
        }
    }
    
    public init(_ item: MethodParameter) {
        self.item = item
    }
}

// MARK: - API property keys (template-facing raw strings)

private enum APIProperty: String, CaseIterable {
    case entity
    case returnType = "return-type"
    case inputType = "input-type"
    case hasPath = "has-path"
    case path
    case name
    case type
    case givenname
    case baseUrl = "base-url"
    case version
    case queryParams = "query-params"
    case isCreate = "is-create"
    case isUpdate = "is-update"
    case isDelete = "is-delete"
    case isGetById = "is-get-by-id"
    case isGetByCustomProps = "is-get-by-custom-props"
    case isList = "is-list"
    case isListByCustomProps = "is-list-by-custom-props"
    case isPushData = "is-push-data"
    case isPushDatalist = "is-push-datalist"
    case isGetByCustomLogic = "is-get-by-custom-logic"
    case isListByCustomLogic = "is-list-by-custom-logic"
    case isMutationByCustomLogic = "is-mutation-by-custom-logic"
    case propertiesInvolved = "properties-involved"
    case isAndConditionForPropertiesInvolved = "is-and-condition-for-properties-involved"
    case customParams = "custom-params"
}

private enum APIParamProperty: String, CaseIterable {
    case propMappingFirst = "prop-mapping-first"
    case paramName = "param-name"
    case hasSecondParamName = "has-second-param-name"
    case secondParamName = "second-param-name"
    case hasMultipleParams = "has-multiple-params"
}

private enum APICustomParameterProperty: String, CaseIterable {
    case name
    case type
    case isArray = "is-array"
}
