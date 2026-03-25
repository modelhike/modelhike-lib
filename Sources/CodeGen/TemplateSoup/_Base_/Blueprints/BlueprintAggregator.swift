//
//  BlueprintAggregator.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

public actor BlueprintAggregator: Sendable {
    var blueprintFinders: [BlueprintFinder] = []

    public func blueprint(named name: String, with pInfo: ParsedInfo) async throws -> any Blueprint {
        for finder in blueprintFinders {
            if await finder.hasBlueprint(named: name) {
                return try await finder.blueprint(named: name, with: pInfo)
            }
        }

        var candidates: [String] = []
        for finder in blueprintFinders {
            candidates.append(contentsOf: await finder.blueprintsAvailable)
        }
        throw EvaluationError.invalidInput(
            Suggestions.lookupFailureMessage(
                "There is no blueprint called '\(name)'.",
                for: name,
                in: candidates,
                availableOptionsLabel: "available blueprints"
            ),
            pInfo
        )
    }

    @discardableResult
    public func add(_ finder: BlueprintFinder) -> Bool {
        blueprintFinders.append(finder)
        return true
    }

    public init(config: OutputConfig) {
        if let path = config.localBlueprintsPath {
            blueprintFinders.append(LocalFileBlueprintFinder(path: path))
        }
        
        blueprintFinders.append(contentsOf: config.blueprints)
    }
}
