//
//  API.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor APIState {
    public let attribs = Attributes()
    public let tags = Tags()
    public let annotations = Annotations()

    public var name: String
    public let givenname: String
    public let dataType: ArtifactKind = .api

    /// Set for entity-level APIs; nil for component-level APIs.
    public let entity: CodeObject?
    /// Set for component-level APIs; nil for entity-level APIs.
    public let component: C4Component?
    public let type: APIType

    public let path: String
    public let baseUrl: String
    /// Optional REST path prefix from `# APIs` bracket markers such as `[/api/v1]`.
    public let routePrefix: String?
    public let version: Int
    public private(set) var queryParams: [APIQueryParamWrapper] = []

    public func append(queryParam: APIQueryParamWrapper) {
        self.queryParams.append(queryParam)
    }

    public func name(_ value: String) {
        self.name = value
    }

    public init(entity item: CodeObject, name: String, path: String, type: APIType, version: Int = 1, routePrefix: String? = nil) async {
        let entityname = await item.name
        self.entity = item
        self.component = nil
        self.type = type
        self.baseUrl = entityname.slugify()
        self.version = version
        self.path = path
        self.routePrefix = routePrefix
        self.name = name
        self.givenname = name
    }

    public init(component item: C4Component, name: String, path: String, type: APIType, version: Int = 1, routePrefix: String? = nil) async {
        let componentName = item.name
        self.component = item
        self.entity = nil
        self.type = type
        self.baseUrl = componentName.slugify()
        self.version = version
        self.path = path
        self.routePrefix = routePrefix
        self.name = name
        self.givenname = name
    }

}

public actor GenericAPI: API {
    public var state: APIState
    public private(set) var name: String = ""

    public init(entity item: CodeObject, type: APIType, version: Int = 1, routePrefix: String? = nil) async {
        let entityname = await item.name
        
        var name = ""
        
        switch type {
        case .getById:
            name = "get\(entityname)ById"
        case .delete:
            name = "delete\(entityname)"
        case .list:
            let plural = entityname.pluralized()
            name = "list\(plural)"
        case .associate: //will be create for the association
            name = "associate\(entityname)"
        case .deassosiate: //will be delete for the association
            name = "deassosiate\(entityname)"
        case .activate:
            name = "activate\(entityname)"
        case .deactivate:
            name = "deactivate\(entityname)"
        case .create:
            name = "add\(entityname)"
        case .update:
            name = "update\(entityname)"
        case .getByCustomProperties:
            name = "get\(entityname)ByCustomProps"
        case .listByCustomProperties:
            let plural = entityname.pluralized()
            name = "list\(plural)ByCustomProps"
        case .getByUsingCustomLogic:
            name = "get\(entityname)ByCustomLogic"
        case .listByUsingCustomLogic:
            name = "list\(entityname)ByCustomLogic"
        case .mutationUsingCustomLogic:
            name = "mutation\(entityname)ByCustomLogic"
        case .pushData:
            let plural = entityname.pluralized()
            name = "\(plural)Subscription"
        case .pushDataList:
            let plural = entityname.pluralized()
            name = "\(plural)Subscription"
        }
        
        await self.init(entity: item, name: name, type: type, version: version, routePrefix: routePrefix)
    }
    
    public init(entity item: CodeObject, name: String, type: APIType, version: Int = 1, routePrefix: String? = nil) async {
        var path: String = ""
        
        switch type {
        case .getById:
            path = ":id"
        case .delete:
            path = ":id"
        case .list:
            path = ""
        case .associate: //will be create for the association
            path = ""
        case .deassosiate: //will be delete for the association
            path = ""
        case .activate:
            path = "activate"
        case .deactivate:
            path = "deactivate"
        case .create:
            path = ""
        case .update:
            path = ""
        case .getByCustomProperties:
            path = ""
        case .listByCustomProperties:
            path = ""
        case .getByUsingCustomLogic:
            path = ""
        case .listByUsingCustomLogic:
            path = ""
        case .mutationUsingCustomLogic:
            path = ""
        case .pushData:
            path = ""
        case .pushDataList:
            path = ""
        }
        
        self.state = await APIState(entity: item, name: name, path: path, type: type, version: version, routePrefix: routePrefix)
        self.name = name
    }
    
    public init(entity item: CodeObject, name: String, path: String, type: APIType, version: Int = 1, routePrefix: String? = nil) async {
        self.state = await APIState(entity: item, name: name, path: path, type: type, version: version, routePrefix: routePrefix)
        self.name = name
    }

    public init(component item: C4Component, path: String, type: APIType, version: Int = 1, routePrefix: String? = nil) async {
        await self.init(component: item, name: item.name, path: path, type: type, version: version, routePrefix: routePrefix)
    }

    public init(component item: C4Component, name: String, path: String, type: APIType, version: Int = 1, routePrefix: String? = nil) async {
        self.state = await APIState(component: item, name: name, path: path, type: type, version: version, routePrefix: routePrefix)
        self.name = name
    }
}

public protocol API : Artifact {
    var state: APIState { get }
}

extension API {
    public var entity: CodeObject? { state.entity }
    public var component: C4Component? { state.component }
    public var givenname: String { state.givenname }
    public var attribs: Attributes { state.attribs }
    public var annotations: Annotations { state.annotations }
    public var tags: Tags { state.tags }
    public var type: APIType { state.type }
    public var dataType: ArtifactKind { state.dataType }
    public var path: String { state.path }
    public var baseUrl: String { state.baseUrl }
    public var routePrefix: String? { state.routePrefix }
    public var version: Int { state.version }

    public var queryParams: [APIQueryParamWrapper] {
        get async { await state.queryParams }
    }
    
    public func get(_ key: String) async -> String? {
        return await queryParams.first(where: {$0.queryParam.name == key})?.propMaping.givenString
    }
    
    public func set(_ key: String, value newValue: String) async {
        let qKey  = QueryParam_KeyMapping(key)
        let qVal  = QueryParam_PropertyNameMapping(newValue)
        let wrapped: APIQueryParamWrapper
        if let entity {
            wrapped = APIQueryParamWrapper(queryParam: qKey, propMaping: qVal, entity: entity)
        } else if let component {
            wrapped = APIQueryParamWrapper(queryParam: qKey, propMaping: qVal, component: component)
        } else {
            preconditionFailure("API has neither an entity nor a component owner")
        }
        
        await state.append(queryParam: wrapped)
    }
    
    public var debugDescription: String { get async {
        var str =  """
                    \(self.name)
                    """
        str += .newLine
        
        return str
    }}
    
}

public enum APIType: Sendable {
    case create, update, delete,
         getById, getByCustomProperties, 
         mutationUsingCustomLogic, getByUsingCustomLogic, listByUsingCustomLogic,
         list, listByCustomProperties,
         pushData, pushDataList,
         associate, deassosiate, activate, deactivate
}

public enum QueryParamKind: Sendable {
    case unKnown, int, string, date
}

actor QueryParamStore {
    private var storage: [String: String] = [:]

    func set(_ key: String, value: String) {
        storage[key] = value
    }

    func get(_ key: String) -> String? {
        return storage[key]
    }
}

public actor APIQueryParamStore {
    private var params: [APIQueryParamWrapper]

    init() {
        self.params = []
    }
    
    init(params: [APIQueryParamWrapper]) {
        self.params = params
    }

    public func getParams() -> [APIQueryParamWrapper] {
        return params
    }

    public func append(_ param: APIQueryParamWrapper) {
        params.append(param)
    }
}

public struct APIQueryParamWrapper: Sendable {
    public var queryParam: QueryParam_KeyMapping
    public var propMaping : QueryParam_PropertyNameMapping
    public var entity: CodeObject? = nil
    public var component: C4Component? = nil

    public init(queryParam: QueryParam_KeyMapping, propMaping: QueryParam_PropertyNameMapping, entity: CodeObject) {
        self.queryParam = queryParam
        self.propMaping = propMaping
        self.entity = entity
    }

    public init(queryParam: QueryParam_KeyMapping, propMaping: QueryParam_PropertyNameMapping, component: C4Component) {
        self.queryParam = queryParam
        self.propMaping = propMaping
        self.component = component
    }
}

public struct QueryParam_KeyMapping : Hashable, Sendable {
    public var name: String
    public var SecondName: String
    public var canHaveMultipleValues: Bool = false
    
    public init(_ name: String) {
        let split = name.split(separator: ",")

        if split.count > 1 {
            self.name = String(split[0]).trim()
            self.SecondName = String(split[1]).trim()
        } else {
            self.name = name.trim()
            self.SecondName = ""
        }
        
        if self.name.hasSuffix("...") {
            self.name = String(self.name.dropLast(3))
            self.canHaveMultipleValues = true
        }
    }
    
    public var hasSecondParamName : Bool {
        return self.SecondName.isNotEmpty
    }
    
    public init(_ name: String, SecondName: String? = nil) {
        self.name = name.trim()
        self.SecondName = SecondName?.trim() ?? ""
        
        if self.name.hasSuffix("...") {
            self.name = String(self.name.dropLast(3))
            self.canHaveMultipleValues = true
        }
    }
}

public struct QueryParam_PropertyNameMapping: Sendable {
    public private(set) var givenString: String
    public var split: [String]
    
    public var first: String {
        return String(split.first!)
    }
    
    public var last: String {
        return String(split.last!)
    }
    
    public var hasMultipleMappings: Bool {
        return split.count > 1
    }
    
    public var properties: [String] {
        return split
    }
    
    public init(_ givenString: String?) {
        self.givenString = givenString ?? ""
        self.split = self.givenString.split(separator: ",").trim()
    }
    
}

public extension CodeObject {
    func getAPIs() async -> APIList {
        let attached = self.attached
        let apis = APIList()
        
        for item in attached {
            if let api = item as? API {
                await apis.append(api)
            }
        }
        return apis
    }
    
    @discardableResult
    func appendAPI(_ type: APIType, routePrefix: String? = nil) async -> API {
        let api = await GenericAPI(entity: self, type: type, routePrefix: routePrefix)
        attached.append(api)
        
        if type == .list {
            if let getAllAnnotation = await self.annotations[AnnotationConstants.listApi] {
                if let mapping = getAllAnnotation as? MappingAnnotation {
                    for item in mapping.mappings {
                        await api.set(item.key, value: item.value)
                    }
                }
            }
        }
        return api
    }
    
    func hasNoAPIs() async -> Bool {
        let apis = await getAPIs()
        
        return await apis.count == 0
    }
}

public extension C4Component {
    func getAPIs() async -> APIList {
        let apis = APIList()
        for item in attached {
            if let api = item as? API {
                await apis.append(api)
            }
        }
        return apis
    }
}
