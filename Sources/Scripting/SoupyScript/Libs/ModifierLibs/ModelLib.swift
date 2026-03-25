//
//  ModelLib.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public struct ModelLib {
    public static func functions(sandbox: Sandbox) async -> [Modifier] {
        return await [
            getObjectWithName(sandbox: sandbox),
            getLastRecursivePropWithName(sandbox: sandbox),
            getAPIsforCodeObject(sandbox: sandbox),
        ]
    }

    public static func getObjectWithName(sandbox: Sandbox) async -> Modifier {
        return await CreateModifier.withoutParams("get-object") {
            (objectName: String, pInfo: ParsedInfo) throws -> CodeObject_Wrap? in

            if let obj = await sandbox.model.types.get(for: objectName) {
                return CodeObject_Wrap(obj)
            } else {
                let candidates = await sandbox.model.types.items.asyncThrowingMap { await $0.name }
                throw Suggestions.objectTypeNotFound(objectName, candidates: candidates, pInfo: pInfo)
            }
        }
    }

    public static func getLastRecursivePropWithName(sandbox: Sandbox) async -> Modifier {
        return await CreateModifier.withParams("get-last-recursive-prop") {
            (propName: String, arguments: [Sendable], pInfo: ParsedInfo) throws -> TypeProperty_Wrap? in

            guard let objectName = arguments.first as? String else { return nil }

            let appModel = await sandbox.model.types
            if let obj = await appModel.get(for: objectName) {
                if let prop = await obj.getLastPropInRecursive(propName, appModel: appModel) {
                    return TypeProperty_Wrap(prop)
                }
                let candidates = await obj.properties.asyncThrowingMap { await $0.name }
                throw Suggestions.invalidPropertyInType(
                    propName,
                    typeName: objectName,
                    candidates: candidates,
                    pInfo: pInfo
                )
            }

            let typeCandidates = await sandbox.model.types.items.asyncThrowingMap { await $0.name }
            throw Suggestions.objectTypeNotFound(objectName, candidates: typeCandidates, pInfo: pInfo)
        }
    }

    public static func getAPIsforCodeObject(sandbox: Sandbox) async -> Modifier {
        return await CreateModifier.withoutParams("apis") {
            (entity: Sendable, pInfo: ParsedInfo) -> [API_Wrap] in

            if let entityName = entity as? String,
               let entity = await sandbox.model.types.get(for: entityName)
            {
                let apis = await entity.getAPIs()
                return await apis.snapshot().compactMap({ API_Wrap($0) })
            } else if let objWrap = entity as? CodeObject_Wrap {
                let apis = await objWrap.item.getAPIs()
                return await apis.snapshot().compactMap({ API_Wrap($0) })
            } else {
                return []
            }
        }
    }
}
