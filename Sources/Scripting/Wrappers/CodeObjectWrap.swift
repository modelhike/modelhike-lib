//
// CodeObject_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor CodeObject_Wrap: ObjectWrapper {
    public let item: CodeObject

    public var attribs: Attributes { get async { await item.attribs }}

    public var properties: [TypeProperty_Wrap] { get async {
        await item.properties.compactMap({ TypeProperty_Wrap($0) })
    }}

    public var apis: [API_Wrap] { get async {
        await self.item.getAPIs().snapshot().compactMap({ return API_Wrap($0) })
    }}

    public var pushDataApis: [API_Wrap] { get async {
        await self.item.getAPIs().snapshot().compactMap({
            let type = await $0.type
            
            if type == .pushData || type == .pushDataList {
                return API_Wrap($0)
            } else {
                return nil
            }
        })
    }}

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        if propname.hasPrefix("has-prop-") {
            let propName = propname.removingPrefix("has-prop-")
            return await item.hasProp(propName)
        }

        let value: Sendable =
            switch propname {
            case "name": await item.name
            case "given-name": await item.givenname
            case "properties":
                if await properties.count > 0 {
                    await properties
                } else {
                    let msg = "properties empty for \(await item.name)"
                    throw TemplateSoup_ParsingError.propertiesEmpty(msg, pInfo)
                }

            case "entity": await item.dataType == .entity
            case "dto": await item.dataType == .dto
            case "common": await item.dataType == .valueType
            case "cache": await item.dataType == .cache
            case "workflow": await item.dataType == .workflow
            case "has-push-apis": await pushDataApis.count != 0
            case "has-any-apis": await apis.count != 0
            case "methods":
                await item.methods.map { MethodObject_Wrap($0) }
            case "has-methods": !(await item.methods.isEmpty)
            default:
                //nothing found; so check in module attributes
                try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
            }

        return value
    }

    private func propertyCandidates() async -> [String] {
        let attributes = await item.attribs.attributesList
        let attributeNames = attributes.map { $0.givenKey }
        let propertyNames = await item.properties.asyncThrowingMap { await $0.name }
        let propertyFlags = propertyNames.map { "has-prop-\($0)" }
        let base = [
            "name",
            "given-name",
            "properties",
            "entity",
            "dto",
            "common",
            "cache",
            "workflow",
            "has-push-apis",
            "has-any-apis",
            "methods",
            "has-methods",
        ]
        return base + propertyFlags + propertyNames + attributeNames
    }

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws -> Sendable? {
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
    
    public var debugDescription: String { get async { await item.debugDescription }}

    public init(_ item: CodeObject) {
        self.item = item
    }
}

public actor TypeProperty_Wrap: ObjectWrapper {
    public let item: Property

    public var attribs: Attributes { item.attribs }
    public var constraintsList: [Constraint_Wrap] { get async {
        await item.constraints.snapshot().map(Constraint_Wrap.init)
    }}

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
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

        let value: Sendable =
            switch propname {
            case "name":
                //if item.type == .id {
                //    "_id"
                //} else {
                await item.name
            //}
            case "is-array": await item.type.isArray
            case "is-object": await item.type.isObject()
            case "is-number": await item.type.isNumeric
            case "is-bool", "is-boolean", "is-yesno": await item.type == .bool
            case "is-string": await item.type == .string
            case "is-id": await item.type == .id
            case "is-any": await item.type == .any
            case "is-date": await item.type.isDate
            case "is-buffer": await item.type == .buffer
            case "is-reference": await item.type.isReference()
            case "is-extended-reference": await item.type.isExtendedReference()
            case "reference-target":
                (await item.type.kind).firstReferenceTarget?.targetName ?? ""
            case "reference-field":
                (await item.type.kind).firstReferenceTarget?.fieldName ?? ""
            case "reference-field-type":
                if let reference = (await item.type.kind).firstReferenceTarget {
                    await reference.resolvedFieldTypeName_ForDebugging() ?? ""
                } else {
                    ""
                }
            case "is-coded-value": await item.type.isCodedValue()
            case "is-custom-type": await item.type.isCustomType
            case "custom-type":
                if case let .customType(typeName) = await item.type.kind {
                    typeName
                } else {
                    ""
                }
            case "obj-type": await item.type.objectString()
            case "is-required": await item.required == .yes
            case "default-value": await item.defaultValue ?? ""
            case "has-default-value": await item.defaultValue != nil
            case "valid-value-set": await item.validValueSet.joined(separator: ", ")
            case "has-valid-value-set": await item.validValueSet.isEmpty == false
            case "constraints": await constraintsList
            case "has-constraints": await constraintsList.isEmpty == false
            default:
                //nothing found; so check in module attributes
                try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
            }

        return value
    }

    private func propertyCandidates() async -> [String] {
        var candidates = [
            "name",
            "is-array",
            "is-object",
            "is-number",
            "is-bool",
            "is-boolean",
            "is-yesno",
            "is-string",
            "is-id",
            "is-any",
            "is-date",
            "is-buffer",
            "is-reference",
            "is-extended-reference",
            "reference-target",
            "reference-field",
            "reference-field-type",
            "is-coded-value",
            "is-custom-type",
            "custom-type",
            "obj-type",
            "is-required",
            "default-value",
            "has-default-value",
            "valid-value-set",
            "has-valid-value-set",
            "constraints",
            "has-constraints"
        ]
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

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws -> Sendable {
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
    
    public var debugDescription: String { get async { await item.debugDescription }}

    public init(_ item: Property) {
        self.item = item
    }
}

public actor Constraint_Wrap: ObjectWrapper {
    public let item: Constraint
    public let attribs = Attributes()
    private let validProperties = ["name", "has-name", "kind", "expression", "rendered", "value", "expr"]

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        switch propname {
        case "name":
            return item.name ?? ""
        case "has-name":
            return item.name != nil
        case "kind":
            return item.name == nil ? "predicate" : "named"
        case "expression", "rendered":
            return ConstraintRenderer.render(item)
        case "value":
            return ConstraintRenderer.renderValue(of: item)
        case "expr":
            return ConstraintExpr_Wrap(item.expr)
        default:
            throw Suggestions.invalidPropertyInCall(propname, candidates: validProperties, pInfo: pInfo)
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
    private let validProperties = ["kind", "rendered", "name", "operator", "value", "lhs", "rhs", "expr", "arguments", "items", "lower", "upper"]

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        switch propname {
        case "kind":
            return kind
        case "rendered":
            return ConstraintRenderer.render(item)
        case "name":
            switch item {
            case .identifier(let name), .function(let name, _):
                return name
            default:
                return ""
            }
        case "operator":
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
        case "value":
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
        case "lhs":
            if case .binary(let lhs, _, _) = item {
                return ConstraintExpr_Wrap(lhs)
            }
            throw Suggestions.invalidPropertyInCall(propname, candidates: validProperties, pInfo: pInfo)
        case "rhs":
            if case .binary(_, _, let rhs) = item {
                return ConstraintExpr_Wrap(rhs)
            }
            throw Suggestions.invalidPropertyInCall(propname, candidates: validProperties, pInfo: pInfo)
        case "expr":
            if case .unary(_, let expr) = item {
                return ConstraintExpr_Wrap(expr)
            }
            if case .grouped(let expr) = item {
                return ConstraintExpr_Wrap(expr)
            }
            throw Suggestions.invalidPropertyInCall(propname, candidates: validProperties, pInfo: pInfo)
        case "arguments":
            if case .function(_, let arguments) = item {
                return arguments.map(ConstraintExpr_Wrap.init)
            }
            throw Suggestions.invalidPropertyInCall(propname, candidates: validProperties, pInfo: pInfo)
        case "items":
            if case .list(let values) = item {
                return values.map(ConstraintExpr_Wrap.init)
            }
            throw Suggestions.invalidPropertyInCall(propname, candidates: validProperties, pInfo: pInfo)
        case "lower":
            if case .between(_, let lower, _) = item {
                return ConstraintExpr_Wrap(lower)
            }
            throw Suggestions.invalidPropertyInCall(propname, candidates: validProperties, pInfo: pInfo)
        case "upper":
            if case .between(_, _, let upper) = item {
                return ConstraintExpr_Wrap(upper)
            }
            throw Suggestions.invalidPropertyInCall(propname, candidates: validProperties, pInfo: pInfo)
        default:
            throw Suggestions.invalidPropertyInCall(propname, candidates: validProperties, pInfo: pInfo)
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
