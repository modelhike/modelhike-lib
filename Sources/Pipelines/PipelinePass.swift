//
//  PipelinePass.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public protocol PipelinePass: Sendable {
}

public protocol DiscoveringPass: PipelinePass {
    func runIn(_ workspace: Workspace, phase: DiscoverPhase) async throws -> Bool
    func canRunIn(phase: DiscoverPhase) async throws -> Bool
}

public protocol LoadingPass: PipelinePass {
    func runIn(_ workspace: Workspace, phase: LoadPhase) async throws -> Bool
    func canRunIn(phase: LoadPhase) async throws -> Bool
}

public protocol HydrationPass: PipelinePass {
    func runIn(phase: HydratePhase) async throws -> Bool
    func canRunIn(phase: HydratePhase) async throws -> Bool
}

public protocol TransformationPass: PipelinePass {
    func runIn(phase: TransformPhase) async throws -> Bool
    func canRunIn(phase: TransformPhase) async throws -> Bool
}

public protocol RenderingPass: PipelinePass {
    func runIn(_ pipeline: Pipeline, phase: RenderPhase) async throws -> Bool
    func canRunIn(phase: RenderPhase) async throws -> Bool
}

public protocol PersistancePass: PipelinePass {
    func runIn(phase: PersistPhase, pipeline: Pipeline) async throws -> Bool
    func canRunIn(phase: PersistPhase, pipeline: Pipeline) async throws -> Bool
}

extension DiscoveringPass {
    public func canRunIn(phase: DiscoverPhase) async -> Bool {
        return true
    }
}

extension LoadingPass {
    public func canRunIn(phase: LoadPhase) async -> Bool {
        return true
    }
}

extension HydrationPass {
    public func canRunIn(phase: HydratePhase) async -> Bool {
        return true
    }
}

extension TransformationPass {
    public func canRunIn(phase: TransformPhase) async -> Bool {
        return true
    }
}

extension RenderingPass {
    public func canRunIn(phase: RenderPhase) async -> Bool {
        return true
    }
}

extension PersistancePass {
    public func canRunIn(phase: PersistPhase, pipeline: Pipeline) async -> Bool {
        return true
    }
}
