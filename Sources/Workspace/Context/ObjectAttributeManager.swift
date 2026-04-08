//
//  ObjectAttributeManager.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor ObjectAttributeManager {

    public func getObjAttributeValue(objName: String, propName: String, with pInfo: ParsedInfo)
    async throws -> Sendable?
    {
        let ctx = pInfo.ctx
        let obj = await ctx.variables[objName]
        
        if propName.firstIndex(of: ".") != nil {  //hierarchial prop name
            if let dynamicLookup = obj as? DynamicMemberLookup {
                return try await getDynamicLookupValue(
                    lookup: dynamicLookup, propName: propName, with: pInfo)
            } else if obj != nil {
                throw TemplateSoup_ParsingError.invalidPropertyAccess(
                    "Cannot access '.\(propName)' on '\(objName)' "
                    + "(value type '\(type(of: obj as Any))' has no properties)", pInfo)
            } else {
                throw Suggestions.variableOrPropertyNotFound(
                    objName,
                    candidates: await ctx.variables.keySnapshot,
                    pInfo: pInfo
                )
            }
        } else { //attributes cannot be hierarchial
            
            //MARK: Check diff attributes in different types of objects
            //Revisit this repitition, in future, if needed
            if let obj = obj as? HasAttributes {
                if await obj.attribs.has(propName) {
                    return await obj.attribs[propName]
                }
            }

            if let obj = obj as? HasAttributes_Actor {
                if await obj.attribs.has(propName) {
                    return await obj.attribs[propName]
                }
            }
            
            if let obj = obj as? HasAsyncAttributes {
                if await obj.attribs.has(propName) {
                    return await obj.attribs[propName]
                }
            }
            
            //MARK: Continue with others
            if let dynamicLookup = obj as? DynamicMemberLookup {
                return try await dynamicLookup.getValueOf(property: propName, with: pInfo)
            }

            if obj != nil {
                throw TemplateSoup_ParsingError.invalidPropertyAccess(
                    "Cannot access '.\(propName)' on '\(objName)' "
                    + "(value type '\(type(of: obj as Any))' has no properties)", pInfo)
            } else {
                let candidates = await ctx.variables.keySnapshot
                throw Suggestions.variableOrPropertyNotFound(objName, candidates: candidates, pInfo: pInfo)
            }
        }
    }

    private func getDynamicLookupValue(
        lookup: DynamicMemberLookup, propName: String, with pInfo: ParsedInfo
    ) async throws -> Sendable? {

        if let dotIndex = propName.firstIndex(of: ".") {  //hierarchial prop name
            let beforeDot = String(propName[..<dotIndex])
            let afterDot = String(propName[propName.index(after: dotIndex)...])

            let value = try await lookup.getValueOf(property: beforeDot, with: pInfo)

            //if the returned value is a dynamic lookup, continue traversing
            if let dynamicLookup = value as? DynamicMemberLookup {
                return try await getDynamicLookupValue(
                    lookup: dynamicLookup, propName: afterDot, with: pInfo)
            } else {
                return value
            }
        } else {
            return try await lookup.getValueOf(property: propName, with: pInfo)
        }
    }

    private func recordObjectAttributeSetDiagnosticIfNeeded(
        path: String,
        oldValue: Sendable?,
        newValue: Sendable?,
        with pInfo: ParsedInfo
    ) async {
        let ctx = pInfo.ctx
        guard let recorder = await ctx.debugRecorder else { return }

        let oldStr = oldValue.map(debugValueString)
        let newStr = newValue.map(debugValueString) ?? ""
        guard oldStr != newStr else { return }

        let eventIndex = await recorder.currentEventCount
        await recorder.captureDelta(eventIndex: eventIndex, variable: path, oldValue: oldStr, newValue: newStr)
        let debugLog = await ctx.debugLog
        debugLog.recordEvent(.variableSet(name: path, oldValue: oldStr, newValue: newStr, source: SourceLocation(from: pInfo)))
    }

    public func setObjAttribute(
        objName: String, propName: String, valueExpression: String, modifiers: [ModifierInstance],
        with pInfo: ParsedInfo
    ) async throws {

        let ctx = pInfo.ctx
        var hasDot = false

        if propName.firstIndex(of: ".") != nil {  //hierarchial prop name
            hasDot = true
        }

        if let dynamicLookup = await ctx.variables[objName] as? DynamicMemberLookup,
           await dynamicLookup.hasSettable(property: propName)
        {
            let oldValue = try? await getObjAttributeValue(objName: objName, propName: propName, with: pInfo)
            let newValue: Sendable?

            if let body = try await ctx.evaluate(expression: valueExpression, with: pInfo) {
                newValue = try await Modifiers.apply(to: body, modifiers: modifiers, with: pInfo)
            } else {
                newValue = nil
            }

            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: newValue,
                with: pInfo
            )
            try await dynamicLookup.setValueOf(property: propName, value: newValue, with: pInfo)
            return
        }

        if hasDot {
            //attributes cannot have hierarchy
            throw TemplateSoup_ParsingError.invalidStmt(pInfo)
        }

        //MARK: Check diff attributes in different types of objects
        //Revisit this repitition, in future, if needed
        if let obj = await ctx.variables[objName] as? HasAttributes {
            let oldValue = await obj.attribs[propName]
            let newValue: Sendable?
            if let body = try await ctx.evaluate(expression: valueExpression, with: pInfo) {
                newValue = try await Modifiers.apply(to: body, modifiers: modifiers, with: pInfo)
            } else {
                newValue = nil
            }

            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: newValue,
                with: pInfo
            )

            if let newValue {
                await obj.attribs.set(propName, value: newValue)
            } else {
                await obj.attribs.removeValue(forKey: propName)
            }
            return
        }
        
        if let obj = await ctx.variables[objName] as? HasAttributes_Actor {
            let oldValue = await obj.attribs[propName]
            let newValue: Sendable?
            if let body = try await ctx.evaluate(expression: valueExpression, with: pInfo) {
                newValue = try await Modifiers.apply(to: body, modifiers: modifiers, with: pInfo)
            } else {
                newValue = nil
            }

            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: newValue,
                with: pInfo
            )

            if let newValue {
                await obj.attribs.set(propName, value: newValue)
            } else {
                await obj.attribs.removeValue(forKey: propName)
            }
            return
        }
        
        if let obj = await ctx.variables[objName] as? HasAsyncAttributes {
            let oldValue = await obj.attribs[propName]
            let newValue: Sendable?
            if let body = try await ctx.evaluate(expression: valueExpression, with: pInfo) {
                newValue = try await Modifiers.apply(to: body, modifiers: modifiers, with: pInfo)
            } else {
                newValue = nil
            }

            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: newValue,
                with: pInfo
            )

            if let newValue {
                await obj.attribs.set(propName, value: newValue)
            } else {
                await obj.attribs.removeValue(forKey: propName)
            }
            return
        }
        
        //MARK:  continue with others
        
        throw TemplateSoup_ParsingError.invalidStmt(pInfo)

    }

    public func setObjAttribute(
        objName: String, propName: String, value: Sendable?, with pInfo: ParsedInfo
    ) async throws {

        let ctx = pInfo.ctx

        var hasDot = false

        if propName.firstIndex(of: ".") != nil {  //hierarchial prop name
            hasDot = true
        }

        let obj = await ctx.variables[objName]
        
        if let dynamicLookup = obj as? DynamicMemberLookup,
           await dynamicLookup.hasSettable(property: propName)
        {
            let oldValue = try? await getObjAttributeValue(objName: objName, propName: propName, with: pInfo)
            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: value,
                with: pInfo
            )
            try await dynamicLookup.setValueOf(property: propName, value: value, with: pInfo)
            return
        }

        if hasDot {
            //attributes cannot have hierarchy
            throw TemplateSoup_ParsingError.invalidStmt(pInfo)
        }

        //MARK: Check diff attributes in different types of objects
        //Revisit this repitition, in future, if needed
        if let obj = obj as? HasAttributes {
            let oldValue = await obj.attribs[propName]
            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: value,
                with: pInfo
            )
            if let value {
                await obj.attribs.set(propName, value: value)
            } else {
                await obj.attribs.removeValue(forKey: propName)
            }
            return
        }

        if let obj = obj as? HasAttributes_Actor {
            let oldValue = await obj.attribs[propName]
            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: value,
                with: pInfo
            )
            if let value {
                await obj.attribs.set(propName, value: value)
            } else {
                await obj.attribs.removeValue(forKey: propName)
            }
            return
        }
        
        if let obj = obj as? HasAsyncAttributes {
            let oldValue = await obj.attribs[propName]
            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: value,
                with: pInfo
            )
            if let value {
                await obj.attribs.set(propName, value: value)
            } else {
                await obj.attribs.removeValue(forKey: propName)
            }
            return
        }
        
        //MARK:  continue with others
        
        throw TemplateSoup_ParsingError.invalidStmt(pInfo)
    }

    public func setObjAttribute(
        objName: String, propName: String, body: String?, modifiers: [ModifierInstance],
        with pInfo: ParsedInfo
    ) async throws {

        let ctx = pInfo.ctx
        var hasDot = false

        if propName.firstIndex(of: ".") != nil {  //hierarchial prop name
            hasDot = true
        }

        if let dynamicLookup = await ctx.variables[objName] as? DynamicMemberLookup,
           await dynamicLookup.hasSettable(property: propName)
        {
            let oldValue = try? await getObjAttributeValue(objName: objName, propName: propName, with: pInfo)
            let newValue: Sendable?

            if let body = body {
                newValue = try await Modifiers.apply(to: body, modifiers: modifiers, with: pInfo)
            } else {
                newValue = nil
            }

            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: newValue,
                with: pInfo
            )
            try await dynamicLookup.setValueOf(property: propName, value: newValue, with: pInfo)
            return
        }

        if hasDot {
            //attributes cannot have hierarchy
            throw TemplateSoup_ParsingError.invalidStmt(pInfo)
        }

        //MARK: Check diff attributes in different types of objects
        //Revisit this repitition, in future, if needed
        if let obj = await ctx.variables[objName] as? HasAttributes {
            let oldValue = await obj.attribs[propName]
            let newValue: Sendable?
            if let body = body {
                newValue = try await Modifiers.apply(to: body, modifiers: modifiers, with: pInfo)
            } else {
                newValue = nil
            }

            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: newValue,
                with: pInfo
            )

            if let newValue {
                await obj.attribs.set(propName, value: newValue)
            } else {
                await obj.attribs.removeValue(forKey: propName)
            }
            return
        }

        if let obj = await ctx.variables[objName] as? HasAttributes_Actor {
            let oldValue = await obj.attribs[propName]
            let newValue: Sendable?
            if let body = body {
                newValue = try await Modifiers.apply(to: body, modifiers: modifiers, with: pInfo)
            } else {
                newValue = nil
            }

            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: newValue,
                with: pInfo
            )

            if let newValue {
                await obj.attribs.set(propName, value: newValue)
            } else {
                await obj.attribs.removeValue(forKey: propName)
            }
            return
        }
        
        if let obj = await ctx.variables[objName] as? HasAsyncAttributes {
            let oldValue = await obj.attribs[propName]
            let newValue: Sendable?
            if let body = body {
                newValue = try await Modifiers.apply(to: body, modifiers: modifiers, with: pInfo)
            } else {
                newValue = nil
            }

            await recordObjectAttributeSetDiagnosticIfNeeded(
                path: "\(objName).\(propName)",
                oldValue: oldValue,
                newValue: newValue,
                with: pInfo
            )

            if let newValue {
                await obj.attribs.set(propName, value: newValue)
            } else {
                await obj.attribs.removeValue(forKey: propName)
            }
            return
        }
        
        //MARK:  continue with others
        
        throw TemplateSoup_ParsingError.invalidStmt(pInfo)
    }

    public init() {
    }
}
