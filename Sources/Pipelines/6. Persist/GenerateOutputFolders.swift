//
//  GenerateFoldersPass.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public struct GenerateOutputFoldersPass : PersistancePass {
    public func runIn(phase: PersistPhase, pipeline: Pipeline) async throws -> Bool {
        
        try await pipeline.config.output.deleteAllFilesAndFolders()

        var totalFilesGenerated: Int = 0
        var totalFoldersGenerated: Int = 0

        let sandboxes = await pipeline.state.generationSandboxes
        try await withThrowingTaskGroup(of: Void.self) { group in
            for sandbox in sandboxes {
                group.addTask {
                    let output = await sandbox.base_generation_dir
                    try await output.persist(with: sandbox.context)
                }
            }
            try await group.waitForAll()
        }

        for sandbox in sandboxes {
            await totalFilesGenerated += sandbox.context.generatedFiles.count
            await totalFoldersGenerated += sandbox.context.generatedFolders.count
        }
        
        print("✅ Generated \(totalFilesGenerated) files, \(totalFoldersGenerated) folders ...")
        return true
    }
}
