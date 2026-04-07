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
    
    public func runIn(_ pipeline: Pipeline, phase: RenderPhase) async throws -> Bool {
        if await phase.config.outputItemType == .container {
            let pInfo = await ParsedInfo.dummyForAppState(with: pipeline.ws.context)
            for container in try await containersToRender(in: phase, pInfo: pInfo) {
                let sandbox = await pipeline.ws.newGenerationSandbox()
                await pipeline.append(sandbox: sandbox)
                let sandboxPInfo = await ParsedInfo.dummyForAppState(with: sandbox.context)

                guard let templatesRepo = try await blueprint(for: container, sandbox: sandbox, pInfo: sandboxPInfo) else {
                    continue  // W307: missing tag — diagnostic already emitted, skip this container
                }
                try await generateCodebase(container: container, usingBlueprint: templatesRepo, sandbox: sandbox)
            }
        }

        return true
    }

    @discardableResult
    public func generateCodebase(container: C4Container, usingBlueprint blueprint: Blueprint, sandbox: GenerationSandbox) async throws -> String? {
        let containerName = await container.name
        let outputFolderSuffix = await outputFolderSuffix(for: container)
        let output = await sandbox.config.output
        let outputPath = output.path / outputFolderSuffix

        print("🛠️ Container used: \(containerName)")
        print("🛠️ Output folder: \(outputPath.string)")

        return try await sandbox.generateFilesFor(container: containerName, usingBlueprint: blueprint, outputFolderSuffix: outputFolderSuffix)
    }

    private func containersToRender(in phase: RenderPhase, pInfo: ParsedInfo) async throws -> [C4Container] {
        let containersToOutput = await phase.config.containersToOutput
        if containersToOutput.isNotEmpty {
            var resolved: [C4Container] = []
            for name in containersToOutput {
                resolved.append(try await resolveContainer(named: name, model: phase.context.model, pInfo: pInfo))
            }
            return resolved
        }
        return await phase.context.model.containers.snapshot()
    }

    private func resolveContainer(named containerName: String, model: AppModel, pInfo: ParsedInfo) async throws -> C4Container {
        if let container = await model.container(named: containerName) {
            return container
        }

        var candidates: [String] = []
        for existingContainer in await model.containers.snapshot() {
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

    private func blueprint(for container: C4Container, sandbox: GenerationSandbox, pInfo: ParsedInfo) async throws -> Blueprint? {
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

    func blueprintName(for container: C4Container, sandbox: GenerationSandbox, pInfo: ParsedInfo) async -> String? {
        if let configuredBlueprintName = await sandbox.config.blueprintName?.trim(),
           configuredBlueprintName.isNotEmpty {
            return configuredBlueprintName
        }

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

    func outputFolderSuffix(for container: C4Container) async -> String {
        if let outputFolderTag = await container.tags[TagConstants.outputFolder],
           let outputFolderSuffix = outputFolderTag.arg?.trim(),
           outputFolderSuffix.isNotEmpty {
            return outputFolderSuffix.normalizeForFolderName()
        }
        return (await container.givenname).normalizeForFolderName()
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
