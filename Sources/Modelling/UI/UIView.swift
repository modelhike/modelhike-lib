//
//  UIView.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public struct UIViewBinding: Sendable {
    public let name: String
    public let typeName: String?
    public let required: RequiredKind
    public let pInfo: ParsedInfo
}

public struct UIViewSection: Sendable {
    public let name: String
    public var controls: [UIViewBinding]
    public let pInfo: ParsedInfo
}

public struct UIViewSlot: Sendable {
    public let name: String
    public let reference: String
    public var directives: [DSLBodyLine]
    public let pInfo: ParsedInfo
}

public struct UIActionHandler: Sendable {
    public let trigger: String
    public var lines: [DSLBodyLine]
    public let pInfo: ParsedInfo
}

public actor UIView: UIObject, HasTechnicalImplications_Actor {
    let sourceLocation: SourceLocation
    
    public let attribs = Attributes()
    public let tags = Tags()
    public let technicalImplications = TechnicalImplications()
    public let annotations = Annotations()
    public var attachedSections = AttachedSections()
    public var attached: [Artifact] = []

    public let givenname: String
    public let name: String
    public var dataType: ArtifactKind = .ui
    public private(set) var description: String?

    public private(set) var directives: [DSLDirective] = []
    public private(set) var bindings: [UIViewBinding] = []
    public private(set) var sections: [UIViewSection] = []
    public private(set) var slots: [UIViewSlot] = []
    public private(set) var actions: [UIActionHandler] = []

    public var methods: [MethodObject] { [] }

    public func setDescription(_ value: String?) {
        description = value
    }

    @discardableResult
    public func appendAttached(_ item: Artifact) -> Self {
        attached.append(item)
        return self
    }

    public func append(directive: DSLDirective) {
        directives.append(directive)
    }

    public func append(binding: UIViewBinding) {
        if sections.isNotEmpty {
            sections[sections.count - 1].controls.append(binding)
        } else {
            bindings.append(binding)
        }
    }

    public func append(section: UIViewSection) {
        sections.append(section)
    }

    public func append(slot: UIViewSlot) {
        slots.append(slot)
    }

    public func appendDirectiveToLastSlot(_ line: DSLBodyLine) {
        guard slots.isNotEmpty else { return }
        slots[slots.count - 1].directives.append(line)
    }

    public func append(action: UIActionHandler) {
        actions.append(action)
    }

    public func appendLineToLastAction(_ line: DSLBodyLine) {
        guard actions.isNotEmpty else { return }
        actions[actions.count - 1].lines.append(line)
    }

    public var debugDescription: String {
        get async {
            "\(name) : ui view controls=\(bindings.count) actions=\(actions.count)"
        }
    }

    public init(name: String, sourceLocation: SourceLocation) {
        self.sourceLocation = sourceLocation
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
    }
}

public protocol UIObject : ArtifactHolderWithAttachedSections, SendableDebugStringConvertible {
    var givenname: String {get}
    var name: String {get}
    var dataType: ArtifactKind {get set}
    
    var methods : [MethodObject] { get async }
    func hasMethod(_ name: String) async -> Bool
    
    func isSameAs(_ obj: UIObject) async -> Bool
}

public extension UIObject {
    
    func hasMethod(_ name: String) async -> Bool {
        return await methods.contains(where: { await $0.name == name})
    }
    
    func isSameAs(_ obj: UIObject) async -> Bool {
        return await self.givenname == obj.givenname
    }
    
    @discardableResult
    func appendAttached(_ item: Artifact) -> Self {
        attached.append(item)
        return self
    }
}
