//
//  AnnotationProcessor.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum AnnotationProcessor {
    public static func process(_ annotation: any Annotation, for obj: HasAttributes_Actor) async throws {
        switch annotation.name {
            case AnnotationConstants.listApi:
                if let cls = obj as? CodeObject {
                    await cls.appendAPI(.list)
                }
            case AnnotationConstants.apisToGenerate:
                var cls: CodeObject?
                var routePrefix: String?

                if let objcls = obj as? CodeObject {
                    cls = objcls
                }

                if let attachedSection = obj as? AttachedSection,
                   let objcls = await attachedSection.containingObject as? CodeObject {
                        cls = objcls
                        routePrefix = await attachedSection.apiRoutePrefix()
                }
            
                if let cls = cls,
                   let valuesAnnotation = annotation as? ValuesAnnotation {
                    for value in valuesAnnotation.values {
                        switch value.lowercased() {
                        case "create": await cls.appendAPI(.create, routePrefix: routePrefix)
                        case "update": await cls.appendAPI(.update, routePrefix: routePrefix)
                        case "delete": await cls.appendAPI(.delete, routePrefix: routePrefix)
                        case "get-by-id": await cls.appendAPI(.getById, routePrefix: routePrefix)
                        case "list": await cls.appendAPI(.list, routePrefix: routePrefix)
                        case "subscribe", "push-data": await cls.appendAPI(.pushData, routePrefix: routePrefix)
                        case "subscribe-list", "push-datalist": await cls.appendAPI(.pushData, routePrefix: routePrefix)
                        case "crud":
                            await cls.appendAPI(.create, routePrefix: routePrefix)
                            await cls.appendAPI(.update, routePrefix: routePrefix)
                            await cls.appendAPI(.delete, routePrefix: routePrefix)
                            await cls.appendAPI(.getById, routePrefix: routePrefix)
                            await cls.appendAPI(.list, routePrefix: routePrefix)
                        case "none":
                            break //nothing to add
                        default :
                            throw Model_ParsingError.invalidAnnotationLine(annotation.pInfo)
                        }
                    }
                    
                }
            default:
            throw Model_ParsingError.invalidAnnotationLine(annotation.pInfo)
        }
    }
}
