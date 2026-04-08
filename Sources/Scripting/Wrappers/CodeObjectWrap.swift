//
// CodeObject_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor CodeObject_Wrap: ObjectWrapper {
    public let item: CodeObject

    private var _cachedProperties: [TypeProperty_Wrap]?
    private var _cachedApis: [API_Wrap]?

    public var attribs: Attributes { get async { await item.attribs } }

    public var properties: [TypeProperty_Wrap] {
        get async {
            if let cached = _cachedProperties { return cached }
            let computed = await item.properties.map { TypeProperty_Wrap($0) }
            _cachedProperties = computed
            return computed
        }
    }

    public var apis: [API_Wrap] {
        get async {
            if let cached = _cachedApis { return cached }
            let computed = await item.getAPIs().snapshot().map { API_Wrap($0) }
            _cachedApis = computed
            return computed
        }
    }

    public var pushDataApis: [API_Wrap] {
        get async {
            var out: [API_Wrap] = []
            for api in await apis {
                if await Self.isPushDataKind(api.item.type) { out.append(api) }
            }
            return out
        }
    }

    private func hasPushDataApi() async -> Bool {
        for api in await apis {
            if await Self.isPushDataKind(api.item.type) { return true }
        }
        return false
    }

    private static func isPushDataKind(_ type: APIType) -> Bool {
        type == .pushData || type == .pushDataList
    }

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws
        -> Sendable?
    {
        if propname.hasPrefix("has-prop-") {
            let propName = propname.removingPrefix("has-prop-")
            return await item.hasProp(propName)
        }

        guard let key = WrapperDynamicPropertyKey.ForCodeObject(rawValue: propname) else {
            //nothing found; so check in module attributes
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        let value: Sendable =
            switch key {
            case .name: await item.name
            case .givenName: await item.givenname
            case .description: await codeObjectDescription()
            case .hasDescription: await codeObjectHasDescription()
            case .properties: await properties

            case .entity: await item.dataType == .entity
            case .dto: await item.dataType == .dto
            case .common: await item.dataType == .valueType
            case .cache: await item.dataType == .cache
            case .workflow: await item.dataType == .workflow
            case .hasPushApis: await hasPushDataApi()
            case .hasAnyApis: (await apis).isNotEmpty
            case .methods: await item.methods.map { MethodObject_Wrap($0) }
            case .hasMethods: (await item.methods).isNotEmpty
            case .hasDbLogic: await hasAnyMethodWithDataAccessLogic()
            case .hasDbTxnLogic: await hasAnyMethodWithTransactionControlLogic()
            case .hasHttpLogic: await hasAnyMethodWithHttpClientLogic()
            case .hasWsLogic: await hasAnyMethodWithWebSocketClientLogic()
            case .hasGrpcLogic: await hasAnyMethodWithGrpcClientLogic()
            }
        return value
    }

    private func codeObjectDescription() async -> String {
        if let d = item as? DomainObject { return await d.description ?? "" }
        if let d = item as? DtoObject { return await d.description ?? "" }
        return ""
    }

    private func codeObjectHasDescription() async -> Bool {
        if let d = item as? DomainObject {
            let desc = await d.description
            return desc.map { $0.isNotEmpty } ?? false
        }
        if let d = item as? DtoObject {
            let desc = await d.description
            return desc.map { $0.isNotEmpty } ?? false
        }
        return false
    }

    /// True if any method uses data-access statement kinds (SQL, queries, DML, etc.) — language-agnostic; blueprints map to e.g. R2DBC `DatabaseClient`.
    private func hasAnyMethodWithDataAccessLogic() async -> Bool {
        for m in await item.methods {
            guard let logic = await m.logic, logic.isNotEmpty else { continue }
            if await logic.containsDataAccessStatement() { return true }
        }
        return false
    }

    /// True if any method uses transaction-control kinds (`transaction`, `commit`, …) — for e.g. `ReactiveTransactionManager` injection.
    private func hasAnyMethodWithTransactionControlLogic() async -> Bool {
        for m in await item.methods {
            guard let logic = await m.logic, logic.isNotEmpty else { continue }
            if await logic.containsTransactionControlStatement() { return true }
        }
        return false
    }

    private func hasAnyMethodWithHttpClientLogic() async -> Bool {
        for m in await item.methods {
            guard let logic = await m.logic, logic.isNotEmpty else { continue }
            if await logic.containsHttpClientStatement() { return true }
        }
        return false
    }

    private func hasAnyMethodWithWebSocketClientLogic() async -> Bool {
        for m in await item.methods {
            guard let logic = await m.logic, logic.isNotEmpty else { continue }
            if await logic.containsWebSocketStatement() { return true }
        }
        return false
    }

    private func hasAnyMethodWithGrpcClientLogic() async -> Bool {
        for m in await item.methods {
            guard let logic = await m.logic, logic.isNotEmpty else { continue }
            if await logic.containsGrpcClientStatement() { return true }
        }
        return false
    }

    private func propertyCandidates() async -> [String] {
        let attributes = await item.attribs.attributesList
        let attributeNames = attributes.map { $0.givenKey }
        let propertyNames = await item.properties.asyncThrowingMap { await $0.name }
        let propertyFlags = propertyNames.map { "has-prop-\($0)" }
        let base = allCodeObjectWrapTemplatePropertyRawValues()
        return base + propertyFlags + propertyNames + attributeNames
    }

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws
        -> Sendable?
    {
        let attribs = await item.attribs
        if await attribs.has(propname) {
            return await attribs[propname]
        } else if let value = RuntimeReflection.getValueOf(
            property: propname, in: item, with: pInfo)
        {
            //chk for the object property using reflection
            //handle whether it is Sendable here itself
            return try CheckSendable(propname, value: value, pInfo: pInfo)
        } else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: await propertyCandidates(),
                pInfo: pInfo
            )
        }
    }

    public var debugDescription: String { get async { await item.debugDescription } }

    public init(_ item: CodeObject) {
        self.item = item
    }
}

public actor TypeProperty_Wrap: ObjectWrapper {
    public let item: Property

    public var attribs: Attributes { item.attribs }
    public var constraintsList: [Constraint_Wrap] {
        get async {
            await item.constraints.snapshot().map(Constraint_Wrap.init)
        }
    }

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws
        -> Sendable?
    {
        if propname.hasPrefix("has-attrib-") {
            let attributeName = propname.removingPrefix("has-attrib-")
            return await item.hasAttrib(attributeName)
        }

        if propname.hasPrefix("attrib-") {
            let attributeName = propname.removingPrefix("attrib-")
            return await item.attribs[attributeName]
        }

        if propname.hasPrefix("has-constraint-") {
            let constraintName = propname.removingPrefix("has-constraint-")
            return await item.hasConstraint(constraintName)
        }

        if propname.hasPrefix("constraint-") {
            let constraintName = propname.removingPrefix("constraint-")
            return await item.constraints[constraintName]
        }

        guard let key = WrapperDynamicPropertyKey.ForTypeProperty(rawValue: propname) else {
            //nothing found; so check in module attributes
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        let value: Sendable =
            switch key {
            case .name: await item.name
            case .isArray: await item.type.isArray
            case .isObject: await item.type.isObject()
            case .isNumber: await item.type.isNumeric
            case .isBool, .isBoolean, .isYesNo: await item.type == .bool
            case .isString: await item.type == .string
            case .isId: await item.type == .id
            case .isAny: await item.type == .any
            case .isDate: await item.type.isDate
            case .isBuffer: await item.type == .buffer
            case .isReference: await item.type.isReference()
            case .isExtendedReference: await item.type.isExtendedReference()
            case .referenceTarget: (await item.type.kind).firstReferenceTarget?.targetName ?? ""
            case .referenceField: (await item.type.kind).firstReferenceTarget?.fieldName ?? ""
            case .referenceFieldType:
                if let reference = (await item.type.kind).firstReferenceTarget {
                    await reference.resolvedFieldTypeName_ForDebugging() ?? ""
                } else {
                    ""
                }
            case .isCodedValue: await item.type.isCodedValue()
            case .isCustomType: await item.type.isCustomType
            case .customType:
                if case .customType(let typeName) = await item.type.kind {
                    typeName
                } else {
                    ""
                }
            case .objType: await item.type.objectString()
            case .isRequired: await item.required == .yes
            case .defaultValue: await item.defaultValue ?? ""
            case .hasDefaultValue: await item.defaultValue != nil
            case .validValueSet: await item.validValueSet.joined(separator: ", ")
            case .hasValidValueSet: await item.validValueSet.isNotEmpty
            case .constraints: await constraintsList
            case .hasConstraints: await constraintsList.isNotEmpty
            case .description: await item.description ?? ""
            case .hasDescription:
                (await item.description).map { $0.isNotEmpty } ?? false
            case .appliedConstraints: await item.appliedConstraints.joined(separator: ", ")
            case .hasAppliedConstraints: await item.appliedConstraints.isNotEmpty
            case .appliedDefaultExpression: await item.appliedDefaultExpression ?? ""
            case .hasAppliedDefaultExpression: await item.appliedDefaultExpression != nil
            }
        return value
    }

    private func propertyCandidates() async -> [String] {
        var candidates = allTypePropertyWrapTemplatePropertyRawValues()
        for attribute in await item.attribs.attributesList {
            candidates.append("attrib-\(attribute.givenKey)")
            candidates.append("has-attrib-\(attribute.givenKey)")
        }
        for constraint in await item.constraints.snapshot() {
            if let name = constraint.name {
                candidates.append("constraint-\(name)")
                candidates.append("has-constraint-\(name)")
            }
        }
        return candidates
    }

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws
        -> Sendable
    {
        if await item.attribs.has(propname) {
            return await item.attribs[propname]
        } else if await item.constraints.has(propname) {
            return await item.constraints[propname]
        } else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: await propertyCandidates(),
                pInfo: pInfo
            )
        }
    }

    public var debugDescription: String { get async { await item.debugDescription } }

    public init(_ item: Property) {
        self.item = item
    }
}

public actor Constraint_Wrap: ObjectWrapper {
    public let item: Constraint
    public let attribs = Attributes()

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws
        -> Sendable?
    {
        guard let key = WrapperDynamicPropertyKey.ForConstraint(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: WrapperDynamicPropertyKey.ForConstraint.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return switch key {
        case .name: item.name ?? ""
        case .hasName: item.name != nil
        case .kind: item.name == nil ? "predicate" : "named"
        case .expression, .rendered: ConstraintRenderer.render(item)
        case .value: ConstraintRenderer.renderValue(of: item)
        case .expr: ConstraintExpr_Wrap(item.expr)
        case .description: item.description ?? ""
        case .hasDescription: item.description.map { $0.isNotEmpty } ?? false
        }
    }

    public var debugDescription: String {
        get async { ConstraintRenderer.render(item) }
    }

    public init(_ item: Constraint) {
        self.item = item
    }
}

public actor ConstraintExpr_Wrap: ObjectWrapper {
    public let item: ConstraintExpr
    public let attribs = Attributes()

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws
        -> Sendable?
    {
        guard let key = WrapperDynamicPropertyKey.ForConstraintExpr(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: WrapperDynamicPropertyKey.ForConstraintExpr.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return try constraintValue(for: key, pInfo: pInfo)
    }

    private func constraintValue(
        for key: WrapperDynamicPropertyKey.ForConstraintExpr, pInfo: ParsedInfo
    ) throws -> Sendable {
        switch key {
        case .kind:
            return kind
        case .rendered:
            return ConstraintRenderer.render(item)
        case .name:
            switch item {
            case .identifier(let name), .function(let name, _):
                return name
            default:
                return ""
            }
        case .op:
            switch item {
            case .unary(let op, _):
                return op.rawValue
            case .binary(_, let op, _):
                return op.rawValue
            case .between:
                return "between"
            default:
                return ""
            }
        case .value:
            switch item {
            case .integer(let value):
                return String(value)
            case .double(let value):
                return String(value)
            case .string(let value):
                return value
            case .boolean(let value):
                return value ? "true" : "false"
            case .null:
                return "nil"
            default:
                return ""
            }
        case .lhs:
            if case .binary(let lhs, _, _) = item {
                return ConstraintExpr_Wrap(lhs)
            }
            throw Suggestions.invalidPropertyInCall(
                key.rawValue,
                candidates: WrapperDynamicPropertyKey.ForConstraintExpr.allCases.map(\.rawValue),
                pInfo: pInfo)
        case .rhs:
            if case .binary(_, _, let rhs) = item {
                return ConstraintExpr_Wrap(rhs)
            }
            throw Suggestions.invalidPropertyInCall(
                key.rawValue,
                candidates: WrapperDynamicPropertyKey.ForConstraintExpr.allCases.map(\.rawValue),
                pInfo: pInfo)
        case .expr:
            if case .unary(_, let expr) = item {
                return ConstraintExpr_Wrap(expr)
            }
            if case .grouped(let expr) = item {
                return ConstraintExpr_Wrap(expr)
            }
            throw Suggestions.invalidPropertyInCall(
                key.rawValue,
                candidates: WrapperDynamicPropertyKey.ForConstraintExpr.allCases.map(\.rawValue),
                pInfo: pInfo)
        case .arguments:
            if case .function(_, let arguments) = item {
                return arguments.map(ConstraintExpr_Wrap.init)
            }
            throw Suggestions.invalidPropertyInCall(
                key.rawValue,
                candidates: WrapperDynamicPropertyKey.ForConstraintExpr.allCases.map(\.rawValue),
                pInfo: pInfo)
        case .items:
            if case .list(let values) = item {
                return values.map(ConstraintExpr_Wrap.init)
            }
            throw Suggestions.invalidPropertyInCall(
                key.rawValue,
                candidates: WrapperDynamicPropertyKey.ForConstraintExpr.allCases.map(\.rawValue),
                pInfo: pInfo)
        case .lower:
            if case .between(_, let lower, _) = item {
                return ConstraintExpr_Wrap(lower)
            }
            throw Suggestions.invalidPropertyInCall(
                key.rawValue,
                candidates: WrapperDynamicPropertyKey.ForConstraintExpr.allCases.map(\.rawValue),
                pInfo: pInfo)
        case .upper:
            if case .between(_, _, let upper) = item {
                return ConstraintExpr_Wrap(upper)
            }
            throw Suggestions.invalidPropertyInCall(
                key.rawValue,
                candidates: WrapperDynamicPropertyKey.ForConstraintExpr.allCases.map(\.rawValue),
                pInfo: pInfo)
        }
    }

    public var debugDescription: String {
        get async { ConstraintRenderer.render(item) }
    }

    public init(_ item: ConstraintExpr) {
        self.item = item
    }

    private var kind: String {
        switch item {
        case .identifier:
            return "identifier"
        case .integer, .double, .string, .boolean, .null:
            return "literal"
        case .function:
            return "function"
        case .list:
            return "list"
        case .unary:
            return "unary"
        case .binary:
            return "binary"
        case .between:
            return "between"
        case .grouped:
            return "grouped"
        }
    }
}

// MARK: - Template-facing dynamic property keys (end of file; string raw values match template / DSL)

private enum WrapperDynamicPropertyKey {
    enum ForCodeObject: String, CaseIterable {
        case name
        case givenName = "given-name"
        case description
        case hasDescription = "has-description"
        case properties
        case entity
        case dto
        case common
        case cache
        case workflow
        case hasPushApis = "has-push-apis"
        case hasAnyApis = "has-any-apis"
        case methods
        case hasMethods = "has-methods"
        case hasDbLogic = "has-db-logic"
        case hasDbTxnLogic = "has-db-txn-logic"
        case hasHttpLogic = "has-http-logic"
        case hasWsLogic = "has-ws-logic"
        case hasGrpcLogic = "has-grpc-logic"
    }

    enum ForTypeProperty: String, CaseIterable {
        case name
        case isArray = "is-array"
        case isObject = "is-object"
        case isNumber = "is-number"
        case isBool = "is-bool"
        case isBoolean = "is-boolean"
        case isYesNo = "is-yesno"
        case isString = "is-string"
        case isId = "is-id"
        case isAny = "is-any"
        case isDate = "is-date"
        case isBuffer = "is-buffer"
        case isReference = "is-reference"
        case isExtendedReference = "is-extended-reference"
        case referenceTarget = "reference-target"
        case referenceField = "reference-field"
        case referenceFieldType = "reference-field-type"
        case isCodedValue = "is-coded-value"
        case isCustomType = "is-custom-type"
        case customType = "custom-type"
        case objType = "obj-type"
        case isRequired = "is-required"
        case defaultValue = "default-value"
        case hasDefaultValue = "has-default-value"
        case validValueSet = "valid-value-set"
        case hasValidValueSet = "has-valid-value-set"
        case constraints
        case hasConstraints = "has-constraints"
        case description
        case hasDescription = "has-description"
        case appliedConstraints = "applied-constraints"
        case hasAppliedConstraints = "has-applied-constraints"
        case appliedDefaultExpression = "applied-default-expression"
        case hasAppliedDefaultExpression = "has-applied-default-expression"
    }

    enum ForConstraint: String, CaseIterable {
        case name
        case hasName = "has-name"
        case kind
        case expression
        case rendered
        case value
        case expr
        case description
        case hasDescription = "has-description"
    }

    enum ForConstraintExpr: String, CaseIterable {
        case kind
        case rendered
        case name
        case op = "operator"
        case value
        case lhs
        case rhs
        case expr
        case arguments
        case items
        case lower
        case upper
    }
}

/// Declared after `WrapperDynamicPropertyKey` at the bottom of this file so `CaseIterable.allCases`
/// is not type-checked inside wrapper actors (Swift otherwise mis-resolves the nested type).
private func allCodeObjectWrapTemplatePropertyRawValues() -> [String] {
    WrapperDynamicPropertyKey.ForCodeObject.allCases.map(\.rawValue)
}

private func allTypePropertyWrapTemplatePropertyRawValues() -> [String] {
    WrapperDynamicPropertyKey.ForTypeProperty.allCases.map(\.rawValue)
}
