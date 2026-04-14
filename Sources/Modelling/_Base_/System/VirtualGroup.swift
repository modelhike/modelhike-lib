//
//  VirtualGroup.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//
//  A named visual grouping within a `C4System`. Virtual groups carry no semantic
//  meaning — they exist purely to communicate spatial or logical clustering of
//  elements in architecture diagrams.
//
//  Syntax inside a system body:
//
//      +--- Infrastructure #tier=data -- Core data services
//      |
//      | PostgreSQL [database]
//      | +++++++++++++++++++++
//      | host = db.internal
//      |
//      | + Payments Service
//      |
//      +---
//
//  Groups nest to arbitrary depth: a body line whose content (after stripping
//  the leading `|`) is itself a `+--- Name` opener starts an inner group.
//

import Foundation

public struct VirtualGroup: Sendable, HasTechnicalImplicationsValues {
    public let name: String
    public let givenname: String
    public var description: String?
    public var tags: [Tag]
    /// Bracket technical-review notes from the group header (after `(attributes)`).
    public var technicalImplications: [TechnicalImplication]

    /// Container names declared with `+ Name` inside this group — unresolved until
    /// `AppModel.resolveAndLinkItems` runs.
    public private(set) var unresolvedContainerRefs: [String]

    /// Resolved `C4Container` references (populated during the load phase).
    public private(set) var containers: [C4Container]

    /// Inline infrastructure elements declared inside this group.
    public private(set) var infraNodes: [InfraNode]

    /// Nested virtual groups, preserving declaration order.
    public private(set) var subGroups: [VirtualGroup]

    public init(givenname: String, description: String? = nil, tags: [Tag] = [], technicalImplications: [TechnicalImplication] = []) {
        self.givenname = givenname.trim()
        self.name = self.givenname.normalizeForVariableName()
        self.description = description
        self.tags = tags
        self.technicalImplications = technicalImplications
        self.unresolvedContainerRefs = []
        self.containers = []
        self.infraNodes = []
        self.subGroups = []
    }

    mutating func appendRef(_ name: String) {
        unresolvedContainerRefs.append(name)
    }

    mutating func resolveRef(_ refName: String, to container: C4Container) {
        containers.append(container)
        unresolvedContainerRefs.removeAll(where: { $0 == refName })
    }

    mutating func appendInfraNode(_ node: InfraNode) {
        infraNodes.append(node)
    }

    mutating func appendSubGroup(_ group: VirtualGroup) {
        subGroups.append(group)
    }

    mutating func setSubGroups(_ newSubGroups: [VirtualGroup]) {
        subGroups = newSubGroups
    }
}
