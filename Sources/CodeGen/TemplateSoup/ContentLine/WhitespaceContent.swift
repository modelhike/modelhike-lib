//
//  WhitespaceContent.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

/// Leading indentation on a template line, parsed separately from literal text so the engine can
/// propagate it to every line of a multi-line `{{ }}` expression result.
public struct WhitespaceContent: ContentLineItem {
    public enum Kind: Sendable, CustomDebugStringConvertible {
        case spaces(Int)
        case tabs(Int)
        case mixed(String)

        public var debugDescription: String {
            switch self {
            case .spaces(let n): return "spaces(\(n))"
            case .tabs(let n): return "tabs(\(n))"
            case .mixed(let s): return "mixed(\(s.debugDescription))"
            }
        }
    }

    public let kind: Kind
    public let pInfo: ParsedInfo
    let level: Int

    public var content: String {
        switch kind {
        case .spaces(let n): return String(repeating: " ", count: n)
        case .tabs(let n): return String(repeating: "\t", count: n)
        case .mixed(let s): return s
        }
    }

    public func execute(with ctx: Context) async throws -> String? {
        content
    }

    public var debugDescription: String {
        "WHITESPACE(\(kind.debugDescription))"
    }

    public init(kind: Kind, pInfo: ParsedInfo, level: Int) {
        self.kind = kind
        self.pInfo = pInfo
        self.level = level
    }
}
