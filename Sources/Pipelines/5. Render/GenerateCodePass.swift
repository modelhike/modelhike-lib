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
        var templatesRepo: Blueprint
        
        //let blueprintName = "api-nestjs-monorepo"
        let blueprintName = "api-springboot-monorepo"
        
        let pInfo = await ParsedInfo.dummyForAppState(with: sandbox.context)
        templatesRepo = try await sandbox.context.blueprint(named: blueprintName, with: pInfo)

        if await !hasRequiredEntryPointScript(
            in: templatesRepo,
            blueprintName: blueprintName,
            sandbox: sandbox,
            pInfo: pInfo
        ) {
            return false
        }

        try await templatesRepo.loadSymbols(to: sandbox)
        
        if await phase.config.outputItemType == .container {
            //if there is only one container in the model, generate for that container
            if await sandbox.model.containers.count == 1, let container = await sandbox.model.containers.first {
                let containerName = await container.name
                try await generateCodebase(container: containerName, usingBlueprintsFrom: templatesRepo, sandbox: sandbox)
            } else if await phase.config.containersToOutput.count > 0 { //get from config
                for container in await phase.config.containersToOutput {
                    try await generateCodebase(container: container, usingBlueprintsFrom: templatesRepo, sandbox: sandbox)
                }
            } else {
                throw EvaluationError.invalidAppState("Please specify a container, container group or system view to output", pInfo)
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

    private func hasRequiredEntryPointScript(
        in templatesRepo: Blueprint,
        blueprintName: String,
        sandbox: GenerationSandbox,
        pInfo: ParsedInfo
    ) async -> Bool {
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
