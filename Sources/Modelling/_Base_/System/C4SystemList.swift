//
//  C4SystemList.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor C4SystemList {
    public private(set) var systems: [C4System] = []

    public func append(_ item: C4System) {
        systems.append(item)
    }

    public func removeAll() {
        systems.removeAll()
    }

    public var count: Int { systems.count }

    public var first: C4System? { systems.first }

    public func snapshot() -> [C4System] {
        return systems
    }

    public var debugDescription: String { get async {
        var str = "systems \(systems.count):" + String.newLine
        for item in systems {
            str += (await item.givenname) + String.newLine
        }
        return str
    }}

    public init() {}
}
