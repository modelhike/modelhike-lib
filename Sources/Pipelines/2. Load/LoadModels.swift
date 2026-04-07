//
//  LoadModelsPass.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public struct LoadModelsPass: LoadingPass {

    public func runIn(_ ws: Workspace, phase: LoadPhase) async throws -> Bool {
        do {
            let repo = await ModelRepositoryFactory.create(for: ws)

            try await repo.loadModel(to: ws.model)
            try await repo.loadGenerationConfigIfAny()

            if await ws.model.types.items.count > 0 {
                await ws.isModelsLoaded(true)

                let domainTypesCount = await ws.model.containers.types.count
                let commonTypesCount = await ws.model.commonModel.types.count
                let containerCount = await ws.model.containers.snapshot().count
                print(
                    "💡 Loaded domain types: \(domainTypesCount), common types: \(commonTypesCount)")

                // Emit modelLoaded debug event
                if let recorder = await ws.config.debugRecorder {
                    await recorder.recordEvent(.modelLoaded(
                        containerCount: containerCount,
                        typeCount: domainTypesCount,
                        commonTypeCount: commonTypesCount
                    ))
                }

                return true

            } else {
                await ws.isModelsLoaded(false)
                print("❌ No model found.")
                return false
            }
        } catch let err {
            await printError(err, workspace: ws)
            if let recorder = await ws.config.debugRecorder, let errWithPInfo = err as? ErrorWithMessageAndParsedInfo {
                await recorder.recordErrorWithStackAndMemory(errWithPInfo, category: errorCategory(for: err))
            }
            print("❌❌ ERROR IN LOADING MODELS ❌❌")
            return false
        }
    }

    fileprivate func printError(_ err: Error, workspace: Workspace) async {
        let printer = PipelineErrorPrinter()
        await printer.printError(err, context: workspace.context)
    }

    fileprivate func errorCategory(for err: Error) -> String {
        switch err {
        case is ParsingError: return "parsing"
        case is Model_ParsingError: return "model-parsing"
        case is EvaluationError: return "evaluation"
        case is TemplateSoup_ParsingError: return "template-syntax"
        case is TemplateSoup_EvaluationError: return "template-evaluation"
        default: return "unknown"
        }
    }

    public init() {
    }
}
