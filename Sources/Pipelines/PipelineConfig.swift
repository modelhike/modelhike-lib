//
//  PipelineConfig.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

public struct PipelineConfig : OutputConfig {
    public var basePath: LocalPath = SystemFolder.documents.path {
        didSet {
            self.output = LocalFolder(path: basePath / "modelhike-output")
        }
    }
    
    public var output : LocalFolder = SystemFolder.documents / "modelhike-output"
    public var outputItemType : OutputArtifactType = .container
    
    public var containersToOutput: [String] = []
    /// Names of ``C4System`` blocks to generate (see `OutputArtifactType.system`).
    public var systemsToOutput: [String] = []

    public var modelSource: ModelSource = .localFileSystem
    
    public var events = CodeGenerationEvents()
    public var flags = ContextDebugFlags()
    public var errorOutput = ErrorOutputOptions()
    
    public var localBlueprintsPath: LocalPath?
    public var blueprintName: String?
    
    public var blueprints: [BlueprintFinder] = []
    
    /// When set, all debug events are captured for the debug console. Used with `--debug` flag.
    public var debugRecorder: (any DebugRecorder)?
    
    /// When set, enables breakpoint stepping. Used with `--debug` flag.
    public var debugStepper: (any DebugStepper)?

    /// When true, the pipeline records total, phase, and pass timings for the current run.
    public var recordPerformance: Bool = false
    
    public init() {}
}

public struct ErrorOutputOptions : Sendable{
    public var includeMemoryVariablesDump: Bool = false
    
    public init() {}
}

public enum BluePrintType {
    case localFileSystem, resources
}

public enum ModelSource: Sendable {
    case localFileSystem
    case inline(InlineModelLoader)
}

public enum OutputArtifactType : Sendable {
    /// Renders ``C4Container`` targets: leaf containers once; composite `(container-group)` / `(microservices)` containers expand to one target per top-level module.
    case container
    case system
}

public protocol OutputConfig: Sendable {
    var basePath: LocalPath {get set}
    
    var outputItemType : OutputArtifactType {get set}
    var containersToOutput: [String] {get set}
    var systemsToOutput: [String] {get set}
    
    var output : LocalFolder {get set}

    var modelSource: ModelSource {get set}
    
    var events : CodeGenerationEvents {get set}
    var flags: ContextDebugFlags {get set}
    var errorOutput: ErrorOutputOptions {get set}
    
    var localBlueprintsPath: LocalPath? {get set}
    var blueprintName: String? {get set}
    
    var blueprints: [BlueprintFinder] {get set}
    
    var debugRecorder: (any DebugRecorder)? {get set}
    var debugStepper: (any DebugStepper)? {get set}
    var recordPerformance: Bool {get set}
}
