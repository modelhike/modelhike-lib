//
//  ModelRepository.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public protocol ModelRepository {
    func loadModel(to model: AppModel) async throws
    func loadGenerationConfigIfAny() async throws
    
    func probeForModelFiles() -> Bool
    func probeForCommonModelFiles() -> Bool
    func probeForGenerationConfig() -> Bool
}

public enum ModelRepositoryFactory {
    public static func create(for ws: Workspace) async -> ModelRepository {
        let config = await ws.config
        switch config.modelSource {
        case .localFileSystem:
            return LocalFileModelLoader(path: config.basePath, with: ws.context)
        case .inline(let loader):
            return loader
        }
    }
}

