import Foundation
#if os(macOS)
import AppKit
#endif
import ModelHike

@main
struct Development: Sendable {
    static func main() async {
        let args = CommandLine.arguments
        let isDebug = args.contains("--debug")
        let isStepping = args.contains("--debug-stepping")
        do {
            if isStepping {
                try await runCodebaseGenerationWithStepping()
            } else if isDebug {
                try await runCodebaseGenerationWithDebug()
            } else {
                try await runCodebaseGeneration()
            }
        } catch {
            print(error)
        }
    }

    // MARK: - Post-mortem debug mode (--debug)
    
    static func runCodebaseGenerationWithDebug() async throws {
        let args = CommandLine.arguments
        let port = parseDebugPort(from: args) ?? 4800
        let devAssetsPath = parseDebugDev(from: args)
        let noOpen = args.contains("--no-open")

        let pipeline = Pipelines.codegen
        var config = Environment.debug
        config.containersToOutput = ["APIs"]

        let recorder = DefaultDebugRecorder()
        config.debugRecorder = recorder
        config.debugStepper = NoOpDebugStepper()

        try await pipeline.run(using: config)

        let session = await recorder.session(config: config)
        let renderedOutputs = await pipeline.state.renderedOutputRecords()
        let server = DebugHTTPServer(
            session: session,
            recorder: recorder,
            pipeline: pipeline,
            renderedOutputs: renderedOutputs,
            port: port,
            devAssetsPath: devAssetsPath,
            serverMode: .postMortem
        )
        try await server.start()

        try? await Task.sleep(nanoseconds: 300_000_000)

        #if os(macOS)
        if !noOpen {
            let url = URL(string: "http://localhost:\(port)")!
            let opened = openURL(url)
            if !opened {
                print("⚠️ Could not open browser automatically. Visit http://localhost:\(port) manually.")
            }
        }
        #endif

        print("✅ Pipeline complete. Debug console at http://localhost:\(port)")
        print("Press Ctrl+C to stop the server.")
        signal(SIGINT) { _ in exit(0) }
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // MARK: - Live stepping mode (--debug-stepping)

    /// Starts the server BEFORE the pipeline so the browser can connect and set
    /// breakpoints. Events are streamed via WebSocket as the pipeline runs.
    /// Execution pauses at breakpoints until the browser sends a resume command.
    static func runCodebaseGenerationWithStepping() async throws {
        let args = CommandLine.arguments
        let port = parseDebugPort(from: args) ?? 4800
        let devAssetsPath = parseDebugDev(from: args)
        let noOpen = args.contains("--no-open")

        let wsManager = WebSocketClientManager()
        let streamingRecorder = StreamingDebugRecorder(wsManager: wsManager)
        let stepper = LiveDebugStepper()

        // Wire the stepper's pause callback → broadcast WSPausedMessage to all clients
        await stepper.setOnPause { location, vars in
            await streamingRecorder.broadcastPaused(location: location, vars: vars)
        }

        // TEST: Add a breakpoint at main.ss line 10 to demonstrate pause/resume
        await stepper.addBreakpoint(BreakpointLocation(fileIdentifier: "main.ss", lineNo: 10))
        print("🔴 Test breakpoint set at main.ss:10")

        let pipeline = Pipelines.codegen
        var config = Environment.debug
        config.containersToOutput = ["APIs"]
        config.debugRecorder = streamingRecorder
        config.debugStepper = stepper

        // Provide an initial session with config so the server knows the output path.
        // Events/files will be populated as the pipeline runs.
        let initialSession = DebugSession(
            timestamp: Date(),
            config: ConfigSnapshot(
                basePath: config.basePath.string,
                outputPath: config.output.path.string,
                containersToOutput: config.containersToOutput
            ),
            phases: [],
            model: ModelSnapshot(containers: []),
            events: [],
            sourceFiles: [],
            files: [],
            errors: [],
            baseSnapshots: [],
            deltaSnapshots: []
        )

        let server = DebugHTTPServer(
            session: initialSession,
            recorder: streamingRecorder.inner,
            pipeline: pipeline,
            renderedOutputs: [],
            port: port,
            devAssetsPath: devAssetsPath,
            serverMode: .stepping,
            wsManager: wsManager,
            stepper: stepper
        )

        try await server.start()
        print("🔌 Stepping server ready at http://localhost:\(port)")
        print("   WebSocket: ws://localhost:\(port)/ws")
        print("   Set breakpoints in the browser, then the pipeline will start in 4 seconds…")

        #if os(macOS)
        if !noOpen {
            let url = URL(string: "http://localhost:\(port)")!
            let opened = openURL(url)
            if !opened {
                print("⚠️ Could not open browser automatically. Visit http://localhost:\(port) manually.")
            }
        }
        #endif

        // Give the browser time to connect and optionally set breakpoints
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        // Run the pipeline — it will pause at any breakpoints set from the browser
        print("▶️  Running pipeline with live stepping enabled…")
        try await pipeline.run(using: config)

        // Pipeline finished — update the REST session and notify browser
        let finalSession = await streamingRecorder.session(config: config)
        let finalOutputs = await pipeline.state.renderedOutputRecords()
        await server.updateSession(finalSession, renderedOutputs: finalOutputs)
        await streamingRecorder.broadcastCompleted()

        print("✅ Pipeline complete. Full session available at http://localhost:\(port)")
        print("Press Ctrl+C to stop the server.")
        signal(SIGINT) { _ in exit(0) }
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // MARK: - Helpers

    #if os(macOS)
    private static func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
    #else
    private static func openURL(_ url: URL) -> Bool { false }
    #endif

    private static func parseDebugPort(from args: [String]) -> UInt16? {
        for arg in args {
            if arg.hasPrefix("--debug-port=") {
                let value = String(arg.dropFirst("--debug-port=".count))
                return UInt16(value)
            }
        }
        return nil
    }

    private static func parseDebugDev(from args: [String]) -> String? {
        guard args.contains("--debug-dev") else { return nil }
        let filePath = #file
        let devTesterDir = (filePath as NSString).deletingLastPathComponent
        return (devTesterDir as NSString).appendingPathComponent("Assets")
    }

    // MARK: - Normal generation (no debug)

    static func runCodebaseGeneration() async throws {
        let pipeline = Pipelines.codegen
        var config = Environment.debug
        config.containersToOutput = ["APIs"]

        //for debugging
        //config.flags.fileGeneration = true
        
//        config.events.onBeforeRenderTemplateFile = { filename, templateName, pInfo in
//            //print(filename)
//            
//            if filename.is("user.java") {
//                pInfo.ctx.debugLog.flags.lineByLineParsing = true
//            } else {
//                pInfo.ctx.debugLog.flags.lineByLineParsing = false
//            }
//            
//            return true
//        }
        
        
//        config.events.onBeforeRenderFile = { filename, context in
//            if filename.lowercased() == "MonitoredLiveAirport".lowercased() {
//                print("rendering \(filename)")
//            }
//
//            return true
//        }
//        
//        config.events.onBeforeParseTemplate = { templatename, context in
//            if templatename.lowercased() == "entity.validator.teso".lowercased() {
//                print("rendering \(templatename)")
//            }
//        }
//
//        config.events.onBeforeExecuteTemplate = { templatename, context in
//            if templatename.lowercased() == "entity.validator.teso".lowercased() {
//                print("rendering \(templatename)")
//            }
//        }
//        
//        config.events.onStartParseObject = { objname, pInfo in
//            print(objname)
//            if objname.lowercased() == "airport".lowercased() {
//                pInfo.ctx.debugLog.flags.lineByLineParsing = true
//            } else {
//                pInfo.ctx.debugLog.flags.lineByLineParsing = false
//            }
//        }
                  
        //continue run
        try await pipeline.run(using: config)
    }
    
    
    private static func inlineModel(_ ws: Workspace) async -> InlineModelLoader {
        return await InlineModelLoader(with: ws.context) {
            InlineModel {
                """
                ===
                APIs
                ====
                + Registry Management
                
                
                === Registry Management ===
                
                Registry
                ========
                * _id: Id
                * name: String
                - desc: String
                * status: CodedValue
                * condition: CodedValue[1..*]
                * speciality: CodedValue
                - author: Reference@StaffRole
                - audit: Audit (backend)
                """
            }
            
            getCommonTypes()
        }
    }
    
    private static func getCommonTypes() -> InlineCommonTypes {
        return InlineCommonTypes {
                """
                === Commons ===
                
                CodedValue
                ==========
                * vsRef: String
                * code: String
                * display: String
                
                Reference
                =========
                * ref: String
                - type: String
                * display: String
                
                ExtendedReference
                =================
                * ref: String
                - type: String
                * display: String
                - info: Any
                - infoType: String
                - avatar: String
                - linkRef: String
                - linkType: String
                
                Audit
                ========
                - ver: String
                - crBy: Reference
                - crDt: Date
                - upDt: Date
                - upBy: Reference
                - srcId: String
                - srcApp: String
                - del: Bool
                """
            }
    }
    
    static func runTemplateStr() async throws {
        let templateStr = "{{ (var1 and var2) and var2}}"
        let arr:[TestData] = await [TestData(name: "n1", age: 1),
                          TestData(name: "n2", age: 2),
                          TestData(name: "", age: 3)]
        
        let data: [String : Sendable] = ["list":arr, "var1" : true, "var2": false, "varstr": "test"]
        
        let ws = Pipelines.empty
        if let result = try await ws.render(string: templateStr, data: data) {
            print(result)
        }
    }
}

actor TestData : DynamicMemberLookup, HasAttributes_Actor {
    public var attribs = Attributes()
    
    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        return await self.attribs[propname]
    }
    
    public init(name: String, age: Int) async {
        await self.attribs.set("name", value: name)
        await self.attribs.set("age", value: name)
    }
}
