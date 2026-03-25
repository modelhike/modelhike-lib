//
//  ValidateModelsPass.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

/// Runs semantic validation after Load + Hydrate, surfacing all issues as structured diagnostics
/// before the Render phase begins. Errors are emitted as warnings (not thrown) so the pipeline
/// can report all problems in one run rather than stopping at the first.
public struct ValidateModelsPass: LoadingPass {

    public func runIn(_ ws: Workspace, phase: LoadPhase) async throws -> Bool {
        let model = await ws.model
        let ctx = ws.context

        guard await model.isModelsLoaded else { return true }
        var totalWarnings = 0

        // Run each check and accumulate results
        totalWarnings += await validateUnresolvedModules(model: model, ctx: ctx)
        totalWarnings += await validateDuplicateTypeNames(model: model, ctx: ctx)
        totalWarnings += await validateDuplicateMemberNames(model: model, ctx: ctx)
        totalWarnings += await validateUnresolvedTypeReferences(model: model, ctx: ctx)

        if totalWarnings > 0 {
            print("⚠️  Validation complete: \(totalWarnings) warning(s). Generation will continue.")
        } else {
            print("✅ Validation complete: no issues found.")
        }

        return true
    }

    // MARK: - Unresolved container module references

    private func validateUnresolvedModules(model: AppModel, ctx: LoadContext) async -> Int {
        var count = 0
        let containers = await model.containers.snapshot()
        for container in containers {
            let unresolved = await container.unresolvedMembers
            let containerName = await container.name
            for member in unresolved {
                count += 1
                // Build suggestions from known module names
                let allNames: [String] = await {
                    var names: [String] = []
                    for c in await model.containers.snapshot() {
                        for comp in await c.components.snapshot() {
                            names.append(await comp.name)
                            names.append(await comp.givenname)
                        }
                    }
                    return names
                }()
                ctx.debugLog.recordLookupDiagnostic(
                    .warning,
                    code: "W303",
                    "Container '\(containerName)': module reference '+ \(member.name)' could not be resolved.",
                    lookup: member.name,
                    in: allNames,
                    availableOptionsLabel: "known modules",
                    source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: member.name, level: 0)
                )
            }
        }
        return count
    }

    // MARK: - Duplicate type names

    private func validateDuplicateTypeNames(model: AppModel, ctx: LoadContext) async -> Int {
        var count = 0
        var seen: [String: String] = [:]  // normalised name → first occurrence description

        let allTypes = await model.types.items
        for type_ in allTypes {
            let name = await type_.name
            let displayName = await type_.givenname
            if let existing = seen[name] {
                count += 1
                ctx.debugLog.recordDiagnostic(
                    .warning,
                    code: "W304",
                    "Duplicate type name '\(name)'. First occurrence: \(existing).",
                    source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: name, level: 0)
                )
            } else {
                seen[name] = displayName
            }
        }
        return count
    }

    // MARK: - Duplicate member names within an entity

    private func validateDuplicateMemberNames(model: AppModel, ctx: LoadContext) async -> Int {
        var count = 0
        let allTypes = await model.types.items
        for type_ in allTypes {
            let typeName = await type_.name
            var seenProps: [String: Bool] = [:]
            for prop in await type_.properties {
                let pName = await prop.name
                if seenProps[pName] != nil {
                    count += 1
                    ctx.debugLog.recordDiagnostic(
                        .warning,
                        code: "W305",
                        "Duplicate property '\(pName)' in type '\(typeName)'.",
                        source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: pName, level: 0)
                    )
                } else {
                    seenProps[pName] = true
                }
            }
            var seenMethods: [String: Bool] = [:]
            for method in await type_.methods {
                let mName = await method.name
                if seenMethods[mName] != nil {
                    count += 1
                    ctx.debugLog.recordDiagnostic(
                        .warning,
                        code: "W306",
                        "Duplicate method '\(mName)' in type '\(typeName)'.",
                        source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: mName, level: 0)
                    )
                } else {
                    seenMethods[mName] = true
                }
            }
        }
        return count
    }

    // MARK: - Unresolved custom type references

    private func validateUnresolvedTypeReferences(model: AppModel, ctx: LoadContext) async -> Int {
        var count = 0
        let knownTypeNames: [String] = await model.types.items.asyncThrowingMap { await $0.name }

        let allTypes = await model.types.items
        for type_ in allTypes {
            let ownerName = await type_.name
            for prop in await type_.properties {
                let propName = await prop.name
                let typeInfo = await prop.type
                let typeName = typeInfo.objectString()

                // Only check custom types that couldn't be resolved
                if typeInfo.isCustomType, !knownTypeNames.contains(typeName) {
                    count += 1
                    ctx.debugLog.recordLookupDiagnostic(
                        .warning,
                        code: "W301",
                        "Type '\(typeName)' referenced by property '\(propName)' in '\(ownerName)' not found.",
                        lookup: typeName,
                        in: knownTypeNames,
                        availableOptionsLabel: "known types",
                        source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: propName, level: 0)
                    )
                }
            }
        }
        return count
    }

    public init() {}
}
