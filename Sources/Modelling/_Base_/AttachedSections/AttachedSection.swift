//
//  AttachedSection.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor AttachedSection: ArtifactHolder, HasTechnicalImplications_Actor {

    public var debugDescription: String {
        return "AttachedSection(\(name))"
    }

    public var attribs = Attributes()
    public var tags = Tags()
    public let technicalImplications = TechnicalImplications()
    public var annotations: Annotations {
        get async { await containingObject.annotations }
    }

    public var name: String = ""
    public var givenname: String = ""
    public private(set) var description: String?
    public let dataType: ArtifactKind = .attachedSection

    public func setDescription(_ value: String?) {
        self.description = value
    }
    internal var containingObject: ArtifactHolderWithAttachedSections

    public internal(set) var items: [Artifact]

    public func appendAttached(_ item: Artifact) {
        self.items.append(item)
    }

    public init(code: String, for obj: ArtifactHolderWithAttachedSections) {
        self.name = code
        self.givenname = code
        self.items = []
        self.containingObject = obj
    }

    /// REST route prefix from bracket markers whose text starts with `/` (e.g. `[/api/v1]`).
    public func apiRoutePrefix() async -> String? {
        let items = await technicalImplications.all()
        return ParserUtil.apiRoutePrefix(from: items)
    }
}
