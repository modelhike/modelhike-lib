//
//  C4Component.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor C4Component: ArtifactHolderWithAttachedSections, HasTechnicalImplications_Actor {
    public let attribs = Attributes()
    public let tags = Tags()
    public let technicalImplications = TechnicalImplications()
    public let annotations = Annotations()
    public var attached: [Artifact] = []
    public var attachedSections = AttachedSections()

    public let name: String
    public let givenname: String
    public let dataType: ArtifactKind = .container
    public private(set) var description: String?
    /// Module-level `=` expressions (computed constants).
    public private(set) var expressions: [Property] = []
    /// Module-level `~` methods / setext functions.
    public private(set) var functions: [MethodObject] = []
    /// Module-level named constraints (`= name : { ... }`).
    public let namedConstraints = Constraints()

    public internal(set) var items: [Artifact] = []

    @discardableResult
    public func appendAttached(_ item: Artifact) -> Self {
        attached.append(item)
        return self
    }

    public func setDescription(_ value: String?) {
        self.description = value
    }

    public func append(expression item: Property) {
        expressions.append(item)
    }

    public func append(function item: MethodObject) {
        functions.append(item)
    }

    public func forEachEntity(by process: (CodeObject) throws -> Void) async throws {
        for item in await types {
            if await item.dataType == .entity { try process(item) }
        }
    }

    private var _cachedTypes: [CodeObject]?

    public var types: [CodeObject] {
        get async {
            if let cached = _cachedTypes { return cached }
            var list: [CodeObject] = []
            for item in items {
                if let component = item as? C4Component {
                    await list.append(contentsOf: component.types)
                } else if let obj = item as? CodeObject {
                    list.append(obj)
                }
            }
            _cachedTypes = list
            return list
        }
    }

    private func invalidateTypesCache() {
        _cachedTypes = nil
    }

    public func append(_ item: CodeObject) {
        items.append(item)
        invalidateTypesCache()
    }

    public func append(_ item: UIObject) {
        items.append(item)
        invalidateTypesCache()
    }

    public func append(submodule item: C4Component) {
        items.append(item)
        invalidateTypesCache()
    }

    public var isEmpty: Bool { items.count == 0 }

    public var debugDescription: String {
        get async {
            let name = self.name
            let count = self.items.count

            var str = """
                \(name)
                | items \(count):
                """
            str += .newLine

            for item in items {
                let givenname = await item.givenname
                str += "| " + givenname + .newLine

            }

            return str
        }
    }

    public init(name: String = "", @ArtifactHolderBuilder _ builder: () -> [ArtifactHolder]) {
        self.name = name.trim().normalizeForVariableName()
        self.givenname = self.name
        self.items = builder()
    }

    public init(name: String = "", _ items: ArtifactHolder...) {
        self.name = name.trim().normalizeForVariableName()
        self.givenname = self.name
        self.items = items
    }

    public init(name: String = "", _ items: [ArtifactHolder]) {
        self.name = name.trim().normalizeForVariableName()
        self.givenname = self.name
        self.items = items
    }

    public init(name: String) {
        self.name = name.trim().normalizeForVariableName()
        self.givenname = self.name
        self.items = []
    }

    public init(name: Substring) {
        self.name = String(name).trim().normalizeForVariableName()
        self.givenname = self.name
        self.items = []
    }

    public init() {
        self.name = ""
        self.givenname = ""
    }
}
