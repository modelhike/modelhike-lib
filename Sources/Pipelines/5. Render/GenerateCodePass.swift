//
//  GenerateCodePass.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public struct GenerateCodePass : RenderingPass {
    public func canRunIn(phase: RenderPhase) async throws -> Bool {

        if await !phase.context.model.isModelsLoaded {
            let pInfo = await ParsedInfo.dummyForAppState(with: phase.context)
            throw EvaluationError.invalidAppState("No models are loaded.", pInfo)
        }
        
        return true
    }
    
    public func runIn(_ sandbox: GenerationSandbox, phase: RenderPhase) async throws -> Bool {
        let pInfo = await ParsedInfo.dummyForAppState(with: sandbox.context)
        
        if await phase.config.outputItemType == .container {
            for container in await containerNamesToRender(in: phase, sandbox: sandbox) {
                guard let templatesRepo = try await blueprint(for: container, sandbox: sandbox, pInfo: pInfo) else {
                    return false
                }
                try await generateCodebase(container: container, usingBlueprintsFrom: templatesRepo, sandbox: sandbox)
            }
        }
                        
        return true
    }
    
    @discardableResult
    public func generateCodebase(container: String, usingBlueprintsFrom blueprintLoader: Blueprint, sandbox: GenerationSandbox) async throws -> String? {
        let output = await sandbox.config.output
        
        print("🛠️ Container used: \(container)")
        print("🛠️ Output folder: \(output.path.string)")
        
        let rendering = try await sandbox.generateFilesFor(container: container, usingBlueprintsFrom: blueprintLoader)
        
        return rendering
    }


    private func containerNamesToRender(in phase: RenderPhase, sandbox: GenerationSandbox) async -> [String] {
        let containersToOutput = await phase.config.containersToOutput
        if !containersToOutput.isEmpty {
            return containersToOutput
        }

        var names: [String] = []
        for container in await sandbox.model.containers.snapshot() {
            names.append(await container.name)
        }
        return names
    }

    private func blueprint(for containerName: String, sandbox: GenerationSandbox, pInfo: ParsedInfo) async throws -> Blueprint? {
        let container = try await container(named: containerName, sandbox: sandbox, pInfo: pInfo)
        guard let blueprintName = await blueprintName(for: container, sandbox: sandbox, pInfo: pInfo) else {
            return nil
        }
        let templatesRepo = try await sandbox.context.blueprint(named: blueprintName, with: pInfo)

        if await !hasRequiredEntryPointScript(in: templatesRepo, blueprintName: blueprintName, sandbox: sandbox, pInfo: pInfo) {
            return nil
        }

        try await templatesRepo.loadSymbols(to: sandbox)
        return templatesRepo
    }

    private func container(named containerName: String, sandbox: GenerationSandbox, pInfo: ParsedInfo) async throws -> C4Container {
        if let container = await sandbox.model.container(named: containerName) {
            return container
        }

        var candidates: [String] = []
        for existingContainer in await sandbox.model.containers.snapshot() {
            candidates.append(await existingContainer.name)
            candidates.append(await existingContainer.givenname)
        }

        throw EvaluationError.invalidInput(
            Suggestions.lookupFailureMessage(
                "There is no container called '\(containerName)'.",
                for: containerName,
                in: candidates,
                availableOptionsLabel: "known containers"
            ),
            pInfo
        )
    }

    func blueprintName(for container: C4Container, sandbox: GenerationSandbox, pInfo: ParsedInfo) async -> String? {
        if let blueprintTag = await container.tags[TagConstants.blueprint],
           let blueprintName = blueprintTag.arg?.trim(),
           blueprintName.isNotEmpty {
            return blueprintName
        }

        let containerName = await container.givenname
        let availableBlueprints = await sandbox.context.blueprints.availableBlueprints
        await sandbox.context.debugLog.recordLookupDiagnostic(
            .warning,
            code: "W307",
            "Container '\(containerName)' is missing '#\(TagConstants.blueprint)(name)' tag — skipping generation.",
            lookup: "",
            in: availableBlueprints,
            availableOptionsLabel: "available blueprints",
            pInfo: pInfo
        )
        return nil
    }
    
    private func hasRequiredEntryPointScript(in templatesRepo: Blueprint, blueprintName: String, sandbox: GenerationSandbox, pInfo: ParsedInfo) async -> Bool {
        // Blueprint pre-flight: verify main.ss exists before committing to generation
        let mainScriptName = TemplateConstants.MainScriptFile + "." + TemplateConstants.ScriptExtension
        if await !templatesRepo.hasFile(mainScriptName) {
            // Try a direct load to see if it exists (most reliable check)
            let mainExists: Bool
            do {
                let _ = try await templatesRepo.loadScriptFile(fileName: TemplateConstants.MainScriptFile, with: pInfo)
                mainExists = true
            } catch {
                mainExists = false
            }
            if !mainExists {
                await sandbox.context.debugLog.recordDiagnostic(
                    .error,
                    code: "E101",
                    "Blueprint '\(blueprintName)' is missing required entry-point '\(mainScriptName)'. Generation cannot proceed.",
                    pInfo: pInfo
                )
                return false
            }
        }

        return true
    }
    
    public init() {
    }
}
