//
//  Pipeline.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public struct Pipeline: Sendable {
    public private(set) var ws: Workspace
    public var debugLog: ContextDebugLog { ws.debugLog }

    let discover: DiscoverPhase
    let load: LoadPhase
    let hydrate: HydratePhase
    let transform: TransformPhase
    let render: RenderPhase
    let persist: PersistPhase
    
    let phases: [any PipelinePhase]
    
    public let state = PipelineState()
    
    public var config: OutputConfig { get async { await ws.config }}
        
    @discardableResult
    public func run(using config: OutputConfig) async throws -> Bool {
        let clock = ContinuousClock()
        let pipelineStart = clock.now

        do {
            await ws.config(config)
            await state.configure(using: config)
            let recorder = config.debugRecorder
            let performanceRecorder = await state.performanceRecorder
            var lastRunResult = true

            await performanceRecorder?.recordPipelineStarted()

            for phase in phases {
                await recorder?.recordPhaseStarted(name: phase.name)
                await performanceRecorder?.recordPhaseStarted(name: phase.name)
                let phaseStart = clock.now
                do {
                    let success = try await phase.runIn(pipeline: self)
                    let phaseDurationMs = PipelinePerformanceTime.milliseconds(from: phaseStart.duration(to: clock.now))
                    await recorder?.recordPhaseCompleted(name: phase.name, success: success, errorMessage: nil)
                    await performanceRecorder?.recordPhaseCompleted(
                        name: phase.name,
                        durationMs: phaseDurationMs,
                        success: success,
                        errorMessage: nil
                    )
                    if !success { lastRunResult = false; break }
                } catch let err {
                    let phaseDurationMs = PipelinePerformanceTime.milliseconds(from: phaseStart.duration(to: clock.now))
                    await recorder?.recordPhaseCompleted(name: phase.name, success: false, errorMessage: String(describing: err))
                    await performanceRecorder?.recordPhaseCompleted(
                        name: phase.name,
                        durationMs: phaseDurationMs,
                        success: false,
                        errorMessage: String(describing: err)
                    )
                    debugLog.pipelineError("❌❌ ERROR OCCURRED IN \(phase.name) Phase ❌❌")
                    throw err
                }
            }

            if let recorder, await ws.model.isModelsLoaded {
                await recorder.captureModel(await ws.model)
            }

            let totalDurationMs = PipelinePerformanceTime.milliseconds(from: pipelineStart.duration(to: clock.now))
            await performanceRecorder?.recordPipelineCompleted(
                durationMs: totalDurationMs,
                success: lastRunResult,
                errorMessage: nil
            )

            return lastRunResult
        } catch let err {
            if let errWithPInfo = err as? ErrorWithMessageAndParsedInfo {
                await printError(err, errWithPInfo.pInfo.ctx)
                // Capture error into debug session so it appears in the visual debugger
                if let recorder = config.debugRecorder {
                    await recorder.recordErrorWithStackAndMemory(errWithPInfo, category: errorCategory(for: err))
                }
            } else if let errWithMessageOnly = err as? ErrorWithMessage {
                debugLog.pipelineError(errWithMessageOnly.infoWithCode)
            }

            let totalDurationMs = PipelinePerformanceTime.milliseconds(from: pipelineStart.duration(to: clock.now))
            let performanceRecorder = await state.performanceRecorder
            await performanceRecorder?.recordPipelineCompleted(
                durationMs: totalDurationMs,
                success: false,
                errorMessage: String(describing: err)
            )

            debugLog.pipelineError("❌❌❌ TERMINATED DUE TO ERROR ❌❌❌")
            return false
        }
    }

    private func errorCategory(for err: Error) -> String {
        switch err {
        case is ParsingError: return "parsing"
        case is Model_ParsingError: return "model-parsing"
        case is EvaluationError: return "evaluation"
        case is TemplateSoup_ParsingError: return "template-syntax"
        case is TemplateSoup_EvaluationError: return "template-evaluation"
        default: return "unknown"
        }
    }
    
    public func render(string input: String, data: [String : Sendable]) async throws -> String? {
        do {
            await ws.config(PipelineConfig())
            
            return try await ws.render(string: input, data: data)
            
        } catch let err {
            if let errWithPInfo = err as? ErrorWithMessageAndParsedInfo {
                await printError(err, errWithPInfo.pInfo.ctx)
            } else if let errWithMessageOnly = err as? ErrorWithMessage {
                debugLog.pipelineError(errWithMessageOnly.infoWithCode)
            }

            debugLog.pipelineError("❌❌❌ TERMINATED DUE TO ERROR ❌❌❌")
            return nil
        }
    }
    
    public func append(sandbox: GenerationSandbox) async {
        await state.append(sandbox: sandbox)
    }
    
    public init(@PipelineBuilder _ builder: () -> [PipelinePass]) {
        ws = Workspace()
        
        let context = ws.context
        var discover = DiscoverPhase(context: context)
        var load = LoadPhase(context: context)
        var hydrate = HydratePhase(context: context)
        var transform = TransformPhase(context: context)
        var render = RenderPhase(context: context)
        var persist = PersistPhase(context: context)
        
        let providedPasses = builder()
        
        for pass in providedPasses {
            if let dp = pass as? DiscoveringPass {
                discover.append(pass: dp)
            } else if let lp = pass as? LoadingPass {
                load.append(pass: lp)
            } else if let hp = pass as? HydrationPass {
                hydrate.append(pass: hp)
            } else if let tp = pass as? TransformationPass {
                transform.append(pass: tp)
            } else if let rp = pass as? RenderingPass {
                render.append(pass: rp)
            } else if let pp = pass as? PersistancePass {
                persist.append(pass: pp)
            }
        }
        
        self.discover = discover
        self.load = load
        self.hydrate = hydrate
        self.transform = transform
        self.render = render
        self.persist = persist

        self.phases = [discover, load, hydrate, transform, render, persist]
    }
    
    public init(from pipe: Pipeline, @PipelineBuilder _ builder: () -> [PipelinePass]) async {
        ws = Workspace()
        
        let context = ws.context
        var discover = DiscoverPhase(context: context)
        var load = LoadPhase(context: context)
        var hydrate = HydratePhase(context: context)
        var transform = TransformPhase(context: context)
        var render = RenderPhase(context: context)
        var persist = PersistPhase(context: context)
        
        let providedPasses = builder()
        
        discover.append(passes: pipe.discover)
        load.append(passes: pipe.load)
        hydrate.append(passes: pipe.hydrate)
        transform.append(passes: pipe.transform)
        render.append(passes: pipe.render)
        persist.append(passes: pipe.persist)

        
        for pass in providedPasses {
            if let dp = pass as? DiscoveringPass {
                discover.append(pass: dp)
            } else if let lp = pass as? LoadingPass {
                load.append(pass: lp)
            } else if let hp = pass as? HydrationPass {
                hydrate.append(pass: hp)
            } else if let tp = pass as? TransformationPass {
                transform.append(pass: tp)
            } else if let rp = pass as? RenderingPass {
                render.append(pass: rp)
            } else if let pp = pass as? PersistancePass {
                persist.append(pass: pp)
            }
        }
        
        self.discover = discover
        self.load = load
        self.hydrate = hydrate
        self.transform = transform
        self.render = render
        self.persist = persist
        
        self.phases = [discover, load, hydrate, transform, render, persist]
    }
    
    fileprivate func printError(_ err: Error, _ context: Context) async {
        let printer = PipelineErrorPrinter()
        await printer.printError(err, context: context)
    }
}

typealias PipelineBuilder = ResultBuilder<PipelinePass>

public actor PipelineState {
    public internal(set) var generationSandboxes: [GenerationSandbox] = []
    public private(set) var performanceRecorder: (any PipelinePerformanceRecorder)?
    
    public func append(sandbox: GenerationSandbox) {
        generationSandboxes.append(sandbox)
    }

    public func configure(using config: OutputConfig) {
        self.performanceRecorder = config.recordPerformance ? DefaultPipelinePerformanceRecorder() : nil
    }
    
    public init() {
    }
}
