//
//  C4System.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor C4System: ArtifactHolder {
    public var attribs = Attributes()
    public var tags = Tags()
    public var annotations = Annotations()

    public var name: String = ""
    public var givenname: String = ""
    public let dataType: ArtifactKind = .container

    public private(set) var description: String?

    public func setDescription(_ value: String?) {
        self.description = value
    }

    public internal(set) var containers = C4ContainerList()

    /// Container names declared with `+` inside a system fence — resolved during load.
    public private(set) var unresolvedContainerRefs: [String] = []

    /// Inline infrastructure elements (databases, brokers, caches, etc.) declared
    /// as plain name lines inside the system body.
    public private(set) var infraNodes: [InfraNode] = []

    /// Named visual groupings (`+--- Name … +---`) declared inside the system body.
    public private(set) var groups: [VirtualGroup] = []

    public func append(_ item: C4Container) async {
        await containers.append(item)
    }

    public func appendUnresolvedRef(_ name: String) {
        unresolvedContainerRefs.append(name)
    }

    public func removeUnresolvedRef(_ name: String) {
        unresolvedContainerRefs.removeAll(where: { $0 == name })
    }

    public func appendInfraNode(_ node: InfraNode) {
        infraNodes.append(node)
    }

    public func appendGroup(_ group: VirtualGroup) {
        groups.append(group)
    }

    /// Replaces the full groups array — used by `AppModel.resolveAndLinkItems`
    /// to write back resolved container references.
    public func setGroups(_ newGroups: [VirtualGroup]) {
        groups = newGroups
    }

    public var count: Int { get async { await containers.count } }

    public func removeAll() async {
        await containers.removeAll()
    }

    public var debugDescription: String {
        get async {
            var str = """
                \(self.name)
                containers \(await self.containers.count):
                """
            str += .newLine

            for item in await containers.snapshot() {
                await str += "  " + item.givenname + .newLine
            }

            if infraNodes.isNotEmpty {
                str += "infra \(infraNodes.count):" + .newLine
                for node in infraNodes {
                    str += "  " + node.givenname + .newLine
                }
            }

            if groups.isNotEmpty {
                str += "groups \(groups.count):" + .newLine
                for g in groups {
                    str += "  +--- " + g.givenname + .newLine
                }
            }

            return str
        }
    }

    public init(name: String) {
        self.givenname = name.trim()
        self.name = self.givenname.normalizeForVariableName()
    }

    public init(name: String, items: C4Container...) async {
        self.givenname = name.trim()
        self.name = self.givenname.normalizeForVariableName()
        await self.containers.append(contentsOf: items)
    }

    public init(name: String, items: [C4Container]) async {
        self.givenname = name.trim()
        self.name = self.givenname.normalizeForVariableName()
        await self.containers.append(contentsOf: items)
    }

    public init(name: String, items: C4ContainerList) {
        self.givenname = name.trim()
        self.name = self.givenname.normalizeForVariableName()
        self.containers = items
    }

    internal init() {
        self.name = ""
        self.givenname = ""
    }
}
