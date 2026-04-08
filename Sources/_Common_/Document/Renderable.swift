//
//  Renderable.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

public protocol Renderable: Sendable {

}

public protocol RenderableRoot: Renderable {
    @discardableResult
    func render(_ config: RenderConfig) -> String
}

extension RenderableRoot {
    public func render() -> String {
        render(RenderConfig())
    }
}

public protocol RenderableNode: Renderable {
    func render(_ config: RenderConfig, level: Int) -> String
}

public struct RenderConfig: Sendable {
    public let minify: Bool
    public let indentationCount: Int
    public let newline: String

    public func indentationSpacing(level: Int) -> String {
        return String(repeating: " ", count: level * indentationCount)
    }

    public init(minify: Bool = false, indentationCount: Int = 4) {
        self.minify = minify
        self.indentationCount = minify ? 0 : indentationCount
        self.newline = minify ? "" : "\n"
    }

    public static let pretty = RenderConfig(minify: false, indentationCount: 2)

}
