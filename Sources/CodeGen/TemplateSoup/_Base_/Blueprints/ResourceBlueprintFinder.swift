//
//  ResourceBlueprintFinder.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor ResourceBlueprintFinder {
    public private(set) var blueprintsRoot: String
    public private(set) var resourceRoot: String
    var bundle: Bundle

    public func blueprint(named name: String, with pInfo: ParsedInfo) async throws -> any Blueprint
    {
        if let ctx = pInfo.ctx as? GenerationContext {
            return ResourceBlueprint(
                blueprint: name, blueprintsRoot: blueprintsRoot, resourceRoot: resourceRoot,
                bundle: bundle, with: ctx)
        } else {
            fatalError(#function + ": unknown context passed")
        }
    }

    public init(bundle: Bundle) {
        self.bundle = bundle
        // SwiftPM's `.copy("Resources/")` in modelhike-blueprints/Package.swift preserves the
        // "Resources" folder name at the bundle root, so the built bundle layout is
        // `Resources/blueprints/<name>/...`, not `blueprints/<name>/...`.
        self.blueprintsRoot = "Resources/blueprints/"
        self.resourceRoot = ""
    }
}
