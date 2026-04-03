//
//  Loop.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

/// Loop metadata for `@loop` in `for` / `forEach`; class (not actor) — single-threaded scope only.
public final class ForLoop_Wrap: DynamicMemberLookup, @unchecked Sendable, SendableDebugStringConvertible {
    public private(set) var item: ForStmt
    public private(set) var FIRST_IN_LOOP = false
    public private(set) var LAST_IN_LOOP = false

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = ForLoopProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: ForLoopProperty.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return switch key {
        case .first: FIRST_IN_LOOP
        case .last: LAST_IN_LOOP
        }
    }

    public func FIRST_IN_LOOP(_ value: Bool) {
        self.FIRST_IN_LOOP = value
    }

    public func LAST_IN_LOOP(_ value: Bool) {
        self.LAST_IN_LOOP = value
    }

    public var debugDescription: String {
        get async {
            let str = """
            FOR stmt (level: \(item.pInfo.level))
            |- forVar: \(item.ForVar)
            |- inVar: \(item.InArrayVar)

            """

            return str
        }
    }

    public init(_ item: ForStmt) {
        self.item = item
    }
}

// MARK: - For-loop property keys (template-facing raw strings)

private enum ForLoopProperty: String, CaseIterable {
    case first
    case last
}
