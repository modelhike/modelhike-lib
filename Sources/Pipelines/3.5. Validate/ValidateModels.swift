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
        totalWarnings += await validateUnresolvedAtReferences(model: model, ctx: ctx)

        if totalWarnings > 0 {
            ctx.debugLog.pipelineProgress("⚠️  Validation complete: \(totalWarnings) warning(s). Generation will continue.")
        } else {
            ctx.debugLog.pipelineProgress("✅ Validation complete: no issues found.")
        }

        return true
    }

    // MARK: - Unresolved container module references

    private func validateUnresolvedModules(model: AppModel, ctx: LoadContext) async -> Int {
        var count = 0
        let containers = await model.containers.snapshot()
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
        for container in containers {
            let unresolved = await container.unresolvedMembers
            let containerName = await container.name
            for member in unresolved {
                let source = await sourceLocation(for: member, fallbackLineContent: member.name)
                count += 1
                ctx.debugLog.recordLookupDiagnostic(
                    .warning,
                    code: "W303",
                    "Container '\(containerName)': module reference '+ \(member.name)' could not be resolved.",
                    lookup: member.name,
                    in: allNames,
                    availableOptionsLabel: "known modules",
                    source: source
                )
            }
        }
        return count
    }

    // MARK: - Duplicate type names

    private func validateDuplicateTypeNames(model: AppModel, ctx: LoadContext) async -> Int {
        var count = 0
        var seen: [String: String] = [:]  // normalised name → first occurrence description

        let allTypes = await allLoadedTypes(model: model)
        for type_ in allTypes {
            let name = await type_.name
            let displayName = await type_.givenname
            if let existing = seen[name] {
                let source = await sourceLocation(for: type_, fallbackLineContent: name)
                count += 1
                ctx.debugLog.recordDiagnostic(
                    .warning,
                    code: "W304",
                    "Duplicate type name '\(name)'. First occurrence: \(existing).",
                    source: source
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
        let allTypes = await allLoadedTypes(model: model)
        for type_ in allTypes {
            let typeName = await type_.name
            var seenProps: [String: Bool] = [:]
            for prop in await type_.properties {
                let pName = await prop.name
                if seenProps[pName] != nil {
                    let source = SourceLocation(from: prop.pInfo)
                    count += 1
                    ctx.debugLog.recordDiagnostic(
                        .warning,
                        code: "W305",
                        "Duplicate property '\(pName)' in type '\(typeName)'.",
                        source: source
                    )
                } else {
                    seenProps[pName] = true
                }
            }
            var seenMethods: [String: Bool] = [:]
            for method in await type_.methods {
                let mName = await method.name
                if seenMethods[mName] != nil {
                    let source = SourceLocation(from: method.pInfo)
                    count += 1
                    ctx.debugLog.recordDiagnostic(
                        .warning,
                        code: "W306",
                        "Duplicate method '\(mName)' in type '\(typeName)'.",
                        source: source
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
        let typeItems = await allLoadedTypes(model: model)
        let knownTypeNamesSet = Set(await typeItems.asyncThrowingMap { await $0.name })
        let knownTypeNamesSorted = knownTypeNamesSet.sorted()

        for type_ in typeItems {
            let ownerName = await type_.name
            for prop in await type_.properties {
                let propName = await prop.name
                let typeInfo = await prop.type
                guard case let .customType(typeName) = typeInfo.kind else {
                    continue
                }

                if !knownTypeNamesSet.contains(typeName) {
                    let source = SourceLocation(from: prop.pInfo)
                    count += 1
                    ctx.debugLog.recordLookupDiagnostic(
                        .warning,
                        code: "W301",
                        "Type '\(typeName)' referenced by property '\(propName)' in '\(ownerName)' not found.",
                        lookup: typeName,
                        in: knownTypeNamesSorted,
                        availableOptionsLabel: "known types",
                        source: source
                    )
                }
            }
        }
        return count
    }

    // MARK: - Unresolved `@name` constraint / expression references

    /// Validates all parsed `@Name` references used as property defaults or applied constraints.
    /// Builds a shared module/common lookup set first, then augments it with per-class named constraints.
    private func validateUnresolvedAtReferences(model: AppModel, ctx: LoadContext) async -> Int {
        var count = 0
        var names = Set<String>()
        // Build a global lookup set of all module/common expressions + named constraints first.
        // We validate references against this shared pool, then widen per-type scope with class-level
        // named constraints before checking that type's properties.
        for comp in await model.commonModel.snapshot() {
            await collectExpressionAndConstraintNames(from: comp, into: &names)
        }
        for c in await model.containers.snapshot() {
            for comp in await c.components.snapshot() {
                await collectExpressionAndConstraintNames(from: comp, into: &names)
            }
        }

        let allNames = Array(names).sorted()
        let knownLower = Set(names.map { $0.lowercased() })

        // Module-level expressions are represented as `Property` values in `component.expressions`,
        // so they can themselves contain `@...` references that need W302 validation.
        for c in await model.containers.snapshot() {
            for comp in await c.components.snapshot() {
                count += await validateAtRefsForComponent(comp, knownLower: knownLower, allNames: allNames, ctx: ctx)
            }
        }

        let allTypes = await allLoadedTypes(model: model)
        for type_ in allTypes {
            let ownerName = await type_.name
            var scopeNames = knownLower
            // DomainObject adds a local scope layer: class-level named constraints are valid only
            // for properties declared on that class, so merge them here before property validation.
            if let dom = type_ as? DomainObject {
                for c in await dom.namedConstraints.snapshot() {
                    if let n = c.name {
                        scopeNames.insert(n.lowercased())
                    }
                }
            }
            for prop in await type_.properties {
                count += await validatePropertyAtRefs(prop, ownerName: ownerName, knownLower: scopeNames, allNames: allNames, ctx: ctx)
            }
        }

        return count
    }

    private func allLoadedTypes(model: AppModel) async -> [CodeObject] {
        var result: [CodeObject] = []

        for component in await model.commonModel.snapshot() {
            await collectTypes(from: component, into: &result)
        }

        for container in await model.containers.snapshot() {
            for component in await container.components.snapshot() {
                await collectTypes(from: component, into: &result)
            }
        }

        return result
    }

    private func collectTypes(from component: C4Component, into result: inout [CodeObject]) async {
        for item in await component.items {
            if let submodule = item as? C4Component {
                await collectTypes(from: submodule, into: &result)
            } else if let type = item as? CodeObject {
                result.append(type)
            }
        }
    }

    /// Adds a component's module-level expression names and named constraint names into one lookup pool.
    private func collectExpressionAndConstraintNames(from component: C4Component, into names: inout Set<String>) async {
        // Expressions and named constraints share the same `@Name` surface syntax, so the validator
        // keeps one combined candidate list for lookup suggestions and case-insensitive resolution.
        for ex in await component.expressions {
            names.insert(await ex.name)
        }
        for c in await component.namedConstraints.snapshot() {
            if let n = c.name {
                names.insert(n)
            }
        }
    }

    /// Reuses property-level `@Name` validation for module-level expressions, which are modelled as `Property`.
    private func validateAtRefsForComponent(_ component: C4Component, knownLower: Set<String>, allNames: [String], ctx: LoadContext) async -> Int {
        var count = 0
        // A module-level expression is parsed as a `Property`, so reuse the property validator.
        for ex in await component.expressions {
            count += await validatePropertyAtRefs(ex, ownerName: await component.name, knownLower: knownLower, allNames: allNames, ctx: ctx)
        }
        return count
    }

    /// Emits W302 diagnostics for unresolved `@Name` references on one property:
    /// both `= @ExpressionName` defaults and `{ @constraintName }` applied constraints.
    private func validatePropertyAtRefs(_ prop: Property, ownerName: String, knownLower: Set<String>, allNames: [String], ctx: LoadContext) async -> Int {
        var count = 0
        // `= @ExpressionName` is stored separately from constraint refs, because it is semantically
        // a default-value expression reference rather than a predicate applied from `{ ... }`.
        if let ref = await prop.appliedDefaultExpression {
            if !knownLower.contains(ref.lowercased()) {
                let source = SourceLocation(from: prop.pInfo)
                count += 1
                ctx.debugLog.recordLookupDiagnostic(
                    .warning,
                    code: "W302",
                    "Unresolved `@\(ref)` default expression reference on property '\(await prop.name)' in '\(ownerName)'.",
                    lookup: ref,
                    in: allNames,
                    availableOptionsLabel: "known expressions/constraints",
                    source: source
                )
            }
        }
        // Constraint refs come from `@Name` entries inside the property's `{ ... }` block.
        for ac in await prop.appliedConstraints {
            if !knownLower.contains(ac.lowercased()) {
                let source = SourceLocation(from: prop.pInfo)
                count += 1
                ctx.debugLog.recordLookupDiagnostic(
                    .warning,
                    code: "W302",
                    "Unresolved `@\(ac)` constraint reference on property '\(await prop.name)' in '\(ownerName)'.",
                    lookup: ac,
                    in: allNames,
                    availableOptionsLabel: "known expressions/constraints",
                    source: source
                )
            }
        }
        return count
    }

    private func sourceLocation(for type_: CodeObject, fallbackLineContent: String) async -> SourceLocation {
        if let domain = type_ as? DomainObject {
            return domain.sourceLocation
        }
        if let dto = type_ as? DtoObject {
            return dto.sourceLocation
        }
        return SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: fallbackLineContent, level: 0)
    }

    private func sourceLocation(for member: ContainerModuleMember, fallbackLineContent: String) async -> SourceLocation {
        let source = member.sourceLocation
        if source.fileIdentifier.isNotEmpty || source.lineNo > 0 {
            return source
        }
        return SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: fallbackLineContent, level: 0)
    }

    public init() {}
}
