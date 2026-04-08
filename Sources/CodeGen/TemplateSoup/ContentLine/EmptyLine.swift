//
//  EmptyLine.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public struct EmptyLine: TemplateItem, StringConvertible, CustomDebugStringConvertible {
    let linesCount: Int
    static public let characters: String = .newLine

    public func execute(with ctx: Context) throws -> String? {
        return .newLine
    }

    public var debugDescription: String {
        return "EMPTY LINE" + .newLine
    }

    public func toString() -> String {
        String(repeating: Self.characters, count: linesCount)
    }

    public init(_ lines: Int) {
        self.linesCount = lines
    }

    public init() {
        self.linesCount = 1
    }
}
