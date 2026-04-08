//
//  Node.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public protocol Node {
    var attributes: Attributes { get set }
}

public protocol ContainerNode: Node {

}

public protocol RestrictedContainerNode: Node {

}

public protocol LeafNode: Node {

}

public protocol LiteralNode: Node, ExpressibleByStringLiteral {
    var text: String { get }
}

public protocol LayoutNode: Node {

}

public protocol RenderAsBlock {

}

public protocol RenderInline {

}

extension LiteralNode {
    public func render(_ config: RenderConfig, level: Int) -> String {
        return text
    }
}

extension Node {
    @discardableResult
    public mutating func attributeIf(_ key: String, value: String?, condition: Bool) async -> Self {
        if condition, let value = value {
            await attributes.set(key, value: value)
        }

        return self
    }

}
