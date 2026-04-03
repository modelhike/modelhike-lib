//
//  AppModel.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor AppModel {
    let types = ParsedTypesCache()
    public internal(set) var commonModel = C4ComponentList()
    private var modules = C4ComponentList()
    public private(set) var containers = C4ContainerList()
    public private(set) var systems = C4SystemList()
    public private(set) var isModelsLoaded = false

    public func resolveAndLinkItems(with ctx: LoadContext) async throws {

        //resolve modules
        await containers.forEach { container in
            for unresolvedMember in await container.unresolvedMembers {
                if let module = await module(named: unresolvedMember.name) {
                    await container.append(module)
                    await container.remove(unResolved: unresolvedMember)
                }
            }
        }

        // Resolve system → container references.
        // A `+ Container Name` line inside a system body is stored as an unresolved ref.
        // Match by givenname first, then by normalised name.
        let containerSnapshot = await containers.snapshot()
        for system in await systems.snapshot() {
            for refName in await system.unresolvedContainerRefs {
                let normalised = refName.normalizeForVariableName()
                if let found = await findContainer(named: refName, normalised: normalised, in: containerSnapshot) {
                    await system.append(found)
                    await system.removeUnresolvedRef(refName)
                }
            }

            // Resolve container refs inside virtual groups (recursively).
            var systemGroups = await system.groups
            for i in systemGroups.indices {
                await resolveGroupRefs(&systemGroups[i], in: containerSnapshot)
            }
            await system.setGroups(systemGroups)
        }
        
        await commonModel.addTypesTo(model: types)
        await containers.addTypesTo(model: types)
        
        // Process mixins and DTO-derived properties first.
        try await containers.forEach { container in
            
            for type in await container.types {
                try await ParserUtil.extractMixins(for: type, with: ctx)
                
                if let dto = type as? DtoObject {
                    try await dto.populateDerivedProperties()
                }
            }
        }

        // Canonicalize custom type names after all properties have been materialized.
        // e.g., the propeties for Dtos are populated only in the above steps
        await containers.forEach { container in
            for type in await container.types {
                for prop in await type.properties {
                    if await prop.type.isCustomType {
                        if let obj = await ctx.model.types.get(for: prop.type.objectString()) {
                            // Change the typename according to the retrieved object; this
                            // correctly fixes the type name even if the given name used a
                            // different casing or contained spaces.
                            await prop.typeKind(.customType(obj.name))
                        }
                    }
                }
            }
        }

        // Resolve all reference-like `Ref@Target.field` types against the loaded model so they store
        // canonical target names and, when a field is specified, the actual field type.
        await containers.forEach { container in
            for type in await container.types {
                for prop in await type.properties {
                    await resolveReferenceTargets(for: prop, in: ctx)
                }
            }
        }
    }
    
    public func container(named name: String) async -> C4Container? {
        return await containers.first(where: {await $0.name == name})
    }

    public func module(named name: String) async -> C4Component? {
        return await modules.first(where: {
            let itemname = await $0.name
            let itemGivenname = await $0.givenname
            return itemname == name || itemGivenname == name
        })
    }
    
    public func appendToCommonModel(contentsOf modelSpace: ModelSpace) async {
        let modelContainers = await modelSpace.containers.snapshot()
        let modelModules = await modelSpace.modules.snapshot()

        for container in modelContainers {
            await commonModel.append(contentsOf: container)
        }
        
        for module in modelModules {
            await commonModel.append(module)
        }
    }
    
    public func append(contentsOf modelSpace: ModelSpace) async {
        let modelSystems = await modelSpace.systems.snapshot()
        let modelContainers = await modelSpace.containers.snapshot()
        let modelModules = await modelSpace.modules.snapshot()

        for system in modelSystems {
            await systems.append(system)
        }

        for container in modelContainers {
            await containers.append(container)
        }
        
        for module in modelModules {
            await modules.append(module)
        }
    }
    
    internal func isModelsLoaded(_ value: Bool) {
        self.isModelsLoaded = value
    }
    
    public init() {
        
    }

    /// Returns the first container whose `givenname` equals `name` or whose normalised
    /// `name` equals `normalised`.
    private func findContainer(named name: String, normalised: String, in snapshot: [C4Container]) async -> C4Container? {
        for container in snapshot {
            let g = await container.givenname
            let n = await container.name
            if g == name || n == normalised { return container }
        }
        return nil
    }

    /// Recursively resolves `+ Container` references inside a `VirtualGroup` and its
    /// nested sub-groups.  Called with an `inout` group so the resolved references are
    /// written back to the caller's value.
    private func resolveGroupRefs(_ group: inout VirtualGroup, in snapshot: [C4Container]) async {
        for refName in group.unresolvedContainerRefs {
            let normalised = refName.normalizeForVariableName()
            if let found = await findContainer(named: refName, normalised: normalised, in: snapshot) {
                group.resolveRef(refName, to: found)
            }
        }
        var resolvedSubs = group.subGroups
        for i in resolvedSubs.indices {
            await resolveGroupRefs(&resolvedSubs[i], in: snapshot)
        }
        group.setSubGroups(resolvedSubs)
    }

    private func resolveReferenceTargets(for property: Property, in ctx: LoadContext) async {
        let kind = await property.type.kind
        guard let targets = kind.referenceTargets, targets.isEmpty == false else {
            return
        }

        // Resolve each parsed reference target against the loaded model so later consumers
        // can work with canonical type/property names instead of the raw DSL spelling.
        var resolvedTargets: [ReferenceTarget] = []
        resolvedTargets.reserveCapacity(targets.count)

        for var reference in targets {
            // If the target type cannot be found yet, keep the parsed reference as-is.
            guard let targetObject = await ctx.model.types.get(for: reference.targetName) else {
                resolvedTargets.append(reference)
                continue
            }

            // Store both the canonical target name and the resolved object handle. The name is
            // what gets rendered/compared; the object lets downstream code inspect the target
            // without resolving it a second time.
            reference.targetName = await targetObject.name
            reference.targetObject = targetObject

            // A reference may also point at a specific property, e.g. Ref@Department.id.
            // When present, canonicalize that property name and keep the resolved property
            // itself so callers can inspect the full type later instead of only a type name.
            if let fieldName = reference.fieldName,
               let targetProperty = await targetObject.getProp(fieldName) {
                reference.fieldName = await targetProperty.name
                reference.fieldProperty = targetProperty
            }

            resolvedTargets.append(reference)
        }

        // Preserve the original reference kind (single, multi, extended, etc.) while swapping
        // in the resolved payloads.
        await property.typeKind(kind.replacingReferenceTargets(resolvedTargets))
    }
}
