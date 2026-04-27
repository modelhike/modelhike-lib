//
//  ConfigObject.swift
//  ModelHike
//

import Foundation

public struct ConfigProperty: Sendable {
    public let key: String
    public let value: String
    public let depth: Int
    public let pInfo: ParsedInfo
}

public struct ConfigGroup: Sendable {
    public let name: String
    public var properties: [ConfigProperty]
    public let pInfo: ParsedInfo
}

public actor ConfigObject: ArtifactHolderWithAttachedSections, HasTechnicalImplications_Actor, HasDescription_Actor {
    let sourceLocation: SourceLocation

    public let attribs = Attributes()
    public let tags = Tags()
    public let technicalImplications = TechnicalImplications()
    public let annotations = Annotations()
    public var attachedSections = AttachedSections()
    public var attached: [Artifact] = []

    public let givenname: String
    public let name: String
    public let dataType: ArtifactKind = .configObject
    public private(set) var description: String?
    public private(set) var configKind: String?
    public private(set) var directives: [DSLDirective] = []
    public private(set) var properties: [ConfigProperty] = []
    public private(set) var groups: [ConfigGroup] = []

    public func setDescription(_ value: String?) {
        description = value
    }

    @discardableResult
    public func appendAttached(_ item: Artifact) -> Self {
        attached.append(item)
        return self
    }

    public func setConfigKind(_ value: String?) {
        configKind = value
    }

    public func append(directive: DSLDirective) {
        directives.append(directive)
    }

    public func append(property: ConfigProperty) {
        if groups.isNotEmpty, property.depth > 0 {
            groups[groups.count - 1].properties.append(property)
        } else {
            properties.append(property)
        }
    }

    public func appendPropertyToLastGroup(_ property: ConfigProperty) {
        if groups.isNotEmpty {
            groups[groups.count - 1].properties.append(property)
        } else {
            properties.append(property)
        }
    }

    public func append(group: ConfigGroup) {
        groups.append(group)
    }

    public var debugDescription: String {
        get async {
            "\(name) : config kind=\(configKind ?? "") properties=\(properties.count)"
        }
    }

    public init(name: String, sourceLocation: SourceLocation) {
        self.sourceLocation = sourceLocation
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
    }
}
