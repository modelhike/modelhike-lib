//
//  DiscoverModelsPass.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public struct DiscoverModelsPass : DiscoveringPass {

    public func runIn(_ ws: Workspace, phase: DiscoverPhase) async throws -> Bool {
        let repo = await ModelRepositoryFactory.create(for: ws)
        
        if repo.probeForGenerationConfig() {
            //print("Generation Config Found!!!")
        }
        
        if repo.probeForCommonModelFiles() {
            //print("Common Model Files Found!!!")
        }
        
        if !repo.probeForModelFiles() {
            ws.debugLog.pipelineError("❌ No model files found.")
            return false
        }
        
        return true
    }
    
    public init() {
    }
}
