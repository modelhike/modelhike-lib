//
//  InlineGenerationHarness.swift
//  ModelHike
//
//  End-to-end codegen with in-memory models and blueprints (tests / quick checks).
//

import Foundation

/// Runs the standard codegen pipeline with ``InlineModel`` / ``InlineBlueprint`` without requiring a filesystem model or blueprint repo.
public enum InlineGenerationHarness {

    /// Runs Discover → Load → Hydrate → Validate → Render (no Persist). Returns merged ``OutputFolder/snapshot()`` strings from every generation sandbox.
    public static func generate(
        model: InlineModel,
        commonTypes: InlineCommonTypes? = nil,
        config: InlineConfig? = nil,
        blueprint: InlineBlueprint,
        containersToOutput: [String] = []
    ) async throws -> [String: String] {
        let pipeline = Pipeline {
            Discover.models()
            Load.models()
            Hydrate.models()
            Hydrate.annotations()
            Validate.models()
            Render.code()
        }
        return try await run(pipeline: pipeline, model: model, commonTypes: commonTypes, config: config, blueprint: blueprint, containersToOutput: containersToOutput, outputOverride: nil)
    }

    /// Full pipeline including Persist into a unique temporary directory. Returns that directory path and the same logical file map as ``generate``.
    public static func generateToTempFolder(
        model: InlineModel,
        commonTypes: InlineCommonTypes? = nil,
        config: InlineConfig? = nil,
        blueprint: InlineBlueprint,
        containersToOutput: [String] = []
    ) async throws -> (path: LocalPath, files: [String: String]) {
        let pipeline = Pipeline {
            Discover.models()
            Load.models()
            Hydrate.models()
            Hydrate.annotations()
            Validate.models()
            Render.code()
            Persist.toOutputFolder()
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("modelhike-inline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        let outPath = LocalPath(tempURL)
        let files = try await run(pipeline: pipeline, model: model, commonTypes: commonTypes, config: config, blueprint: blueprint, containersToOutput: containersToOutput, outputOverride: outPath)
        return (outPath, files)
    }

    private static func run(
        pipeline: Pipeline,
        model: InlineModel,
        commonTypes: InlineCommonTypes?,
        config: InlineConfig?,
        blueprint: InlineBlueprint,
        containersToOutput: [String],
        outputOverride: LocalPath?
    ) async throws -> [String: String] {
        let context = pipeline.ws.context
        var protos: [any InlineModelProtocol] = []
        if let commonTypes {
            protos.append(commonTypes)
        }
        protos.append(model)
        if let cfg = config {
            protos.append(cfg)
        }
        
        let loader = InlineModelLoader(with: context, items: protos)
        let bpName = blueprint.blueprintName
        let finder = InlineBlueprintFinder { blueprint }
        let tempRoot = outputOverride ?? LocalPath(FileManager.default.temporaryDirectory.appendingPathComponent("modelhike-inline-\(UUID().uuidString)", isDirectory: true).path)
        if outputOverride == nil {
            try FileManager.default.createDirectory(at: tempRoot.url, withIntermediateDirectories: true)
        }

        var pipelineConfig = PipelineConfig()
        pipelineConfig.modelSource = .inline(loader)
        pipelineConfig.blueprints = [finder]
        pipelineConfig.blueprintName = bpName
        pipelineConfig.output = LocalFolder(path: tempRoot)
        if !containersToOutput.isEmpty {
            pipelineConfig.containersToOutput = containersToOutput
        }

        _ = try await pipeline.run(using: pipelineConfig)
        var merged: [String: String] = [:]
        let sandboxes = await pipeline.state.generationSandboxes
        for sandbox in sandboxes {
            let snap = await sandbox.base_generation_dir.snapshot()
            for (k, v) in snap {
                merged[k] = v
            }
        }
        return merged
    }
}
