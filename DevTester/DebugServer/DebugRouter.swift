//
//  DebugRouter.swift
//  DevTester
//

import Foundation
import ModelHike

// MARK: - Route response

struct HTTPRouteResponse {
    let status: UInt
    let contentType: String
    let body: Data

    static func ok(body: Data, contentType: String = "application/json") -> HTTPRouteResponse {
        HTTPRouteResponse(status: 200, contentType: contentType, body: body)
    }

    static func ok(body: String, contentType: String = "application/json") -> HTTPRouteResponse {
        HTTPRouteResponse(status: 200, contentType: contentType, body: Data(body.utf8))
    }

    static func notFound() -> HTTPRouteResponse {
        HTTPRouteResponse(status: 404, contentType: "text/plain", body: Data())
    }

    static func notImplemented(_ message: String = "Not Implemented") -> HTTPRouteResponse {
        HTTPRouteResponse(status: 501, contentType: "text/plain", body: Data(message.utf8))
    }

    static func noContent() -> HTTPRouteResponse {
        HTTPRouteResponse(status: 204, contentType: "text/plain", body: Data())
    }
}

// MARK: - Inbound request (assembled by HTTPChannelHandler)

struct InboundHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?
}

// MARK: - Server mode (exposed to browser via /api/mode)

enum DebugServerMode: String, Codable, Sendable {
    case postMortem
    case stepping
}

// MARK: - DebugRouter

actor DebugRouter {

    private var session: DebugSession
    private var renderedOutputs: [RenderedOutputRecord]
    private let recorder: DefaultDebugRecorder?
    private let pipeline: Pipeline?
    private let devAssetsPath: String?
    private let serverMode: DebugServerMode
    private let stepper: LiveDebugStepper?

    init(
        session: DebugSession,
        renderedOutputs: [RenderedOutputRecord] = [],
        recorder: DefaultDebugRecorder? = nil,
        pipeline: Pipeline? = nil,
        devAssetsPath: String? = nil,
        serverMode: DebugServerMode = .postMortem,
        stepper: LiveDebugStepper? = nil
    ) {
        self.session = session
        self.renderedOutputs = renderedOutputs
        self.recorder = recorder
        self.pipeline = pipeline
        self.devAssetsPath = devAssetsPath
        self.serverMode = serverMode
        self.stepper = stepper
    }

    // MARK: - Session update (used in --debug-stepping after pipeline completes)

    func updateSession(_ newSession: DebugSession, renderedOutputs newOutputs: [RenderedOutputRecord]) {
        session = newSession
        renderedOutputs = newOutputs
    }

    // MARK: - Main dispatch

    func handle(_ request: InboundHTTPRequest) async -> HTTPRouteResponse {
        switch request.method {
        case "OPTIONS":
            return .noContent()
        case "GET":
            return await handleGet(path: request.path)
        case "POST":
            return await handlePost(path: request.path, body: request.body)
        default:
            return .notFound()
        }
    }

    // MARK: - GET routing

    private func handleGet(path: String) async -> HTTPRouteResponse {
        if path.hasPrefix("/api/memory/") {
            let indexStr = String(path.dropFirst("/api/memory/".count))
            if let index = Int(indexStr), let recorder {
                let vars = await recorder.reconstructState(atEventIndex: index)
                if let data = try? JSONEncoder().encode(vars) {
                    return .ok(body: data)
                }
            }
            return .notFound()
        }

        let pathWithoutQuery = path.split(separator: "?").first.map(String.init) ?? path

        if pathWithoutQuery.hasPrefix("/api/source/") {
            let raw = String(pathWithoutQuery.dropFirst("/api/source/".count))
            return await serveSource(identifier: raw.removingPercentEncoding ?? raw)
        }

        if pathWithoutQuery.hasPrefix("/api/generated-file/") {
            let indexStr = String(pathWithoutQuery.dropFirst("/api/generated-file/".count))
            if let index = Int(indexStr) {
                return serveGeneratedFile(at: index)
            }
            return .notFound()
        }

        switch pathWithoutQuery {
        case "/", "":
            return serveIndexHTML()
        case "/api/session":
            return serveSession()
        case "/api/model":
            return serveModel()
        case "/api/events":
            return serveEvents()
        case "/api/files":
            return serveFiles()
        case "/api/mode":
            return serveMode()
        case "/api/pause-state":
            return await servePauseState()
        default:
            if pathWithoutQuery.hasPrefix("/styles/") ||
               pathWithoutQuery.hasPrefix("/components/") ||
               pathWithoutQuery.hasPrefix("/utils/") ||
               pathWithoutQuery.hasPrefix("/lib/") {
                return serveStaticFile(path: pathWithoutQuery)
            }
            return .notFound()
        }
    }

    // MARK: - POST routing

    private func handlePost(path: String, body: Data?) async -> HTTPRouteResponse {
        switch path {
        case "/api/evaluate":
            return await serveEvaluate(body: body)
        default:
            return .notFound()
        }
    }

    // MARK: - Route handlers

    private func serveMode() -> HTTPRouteResponse {
        let modeString = "\"\(serverMode.rawValue)\""
        return .ok(body: modeString)
    }

    private func servePauseState() async -> HTTPRouteResponse {
        guard let stepper = stepper else {
            return .ok(body: "null")
        }
        guard let pauseState = await stepper.getPauseState() else {
            return .ok(body: "null")
        }
        // Return same structure as WSPausedMessage
        struct PauseResponse: Encodable {
            let type: String = "paused"
            let location: SourceLocation
            let vars: [String: String]
        }
        let response = PauseResponse(location: pauseState.location, vars: pauseState.vars)
        if let data = try? JSONEncoder().encode(response),
           let json = String(data: data, encoding: .utf8) {
            return .ok(body: json)
        }
        return .ok(body: "null")
    }

    private func serveIndexHTML() -> HTTPRouteResponse {
        if let devPath = devAssetsPath {
            let url = URL(fileURLWithPath: devPath).appendingPathComponent("debug-console/index.html")
            if let data = try? Data(contentsOf: url),
               let html = String(data: data, encoding: .utf8) {
                return .ok(body: html, contentType: "text/html")
            }
        }

        let bundleCandidates: [URL?] = [
            Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Assets/debug-console"),
            Bundle.module.url(forResource: "debug-console/index", withExtension: "html", subdirectory: "Assets")
        ]
        for candidate in bundleCandidates {
            if let url = candidate,
               let data = try? Data(contentsOf: url),
               let html = String(data: data, encoding: .utf8) {
                return .ok(body: html, contentType: "text/html")
            }
        }

        let fallback = """
        <!DOCTYPE html><html><head><title>ModelHike Debug</title></head><body>
        <h1>ModelHike Debug Console</h1>
        <p>Session: \(session.events.count) events. <a href="/api/session">Download JSON</a></p>
        </body></html>
        """
        return .ok(body: fallback, contentType: "text/html")
    }

    private func serveStaticFile(path: String) -> HTTPRouteResponse {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path

        if let devPath = devAssetsPath {
            let url = URL(fileURLWithPath: devPath).appendingPathComponent("debug-console/\(cleanPath)")
            if let data = try? Data(contentsOf: url) {
                return .ok(body: data, contentType: mimeType(forPath: cleanPath))
            }
        }

        let bundleCandidates: [URL?] = [
            Bundle.module.url(forResource: cleanPath, withExtension: nil, subdirectory: "Assets/debug-console"),
            Bundle.module.url(forResource: "debug-console/\(cleanPath)", withExtension: nil, subdirectory: "Assets")
        ]
        for candidate in bundleCandidates {
            if let url = candidate, let data = try? Data(contentsOf: url) {
                return .ok(body: data, contentType: mimeType(forPath: cleanPath))
            }
        }

        return .notFound()
    }

    func mimeType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "woff", "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }

    private func serveSession() -> HTTPRouteResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else {
            return .ok(body: "{}")
        }
        return .ok(body: data)
    }

    private func serveModel() -> HTTPRouteResponse {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(session.model) else {
            return .ok(body: "{}")
        }
        return .ok(body: data)
    }

    private func serveEvents() -> HTTPRouteResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session.events) else {
            return .ok(body: "[]")
        }
        return .ok(body: data)
    }

    private func serveFiles() -> HTTPRouteResponse {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(session.files) else {
            return .ok(body: "[]")
        }
        return .ok(body: data)
    }

    private func serveSource(identifier: String) async -> HTTPRouteResponse {
        guard let file = await sourceFile(for: identifier) else {
            return .notFound()
        }
        struct SourceResponse: Encodable {
            let identifier: String
            let content: String
            let lineCount: Int
        }
        let response = SourceResponse(identifier: file.identifier, content: file.content, lineCount: file.lineCount)
        guard let data = try? JSONEncoder().encode(response) else {
            return .notFound()
        }
        return .ok(body: data)
    }

    private func serveGeneratedFile(at index: Int) -> HTTPRouteResponse {
        guard session.files.indices.contains(index) else {
            return .notFound()
        }
        let record = session.files[index]
        let candidates = generatedFileCandidates(for: record)
        guard let rendered = renderedOutputs.first(where: { candidates.contains(normalizePath($0.path)) }) else {
            return .notFound()
        }
        struct GeneratedFileResponse: Encodable {
            let path: String
            let resolvedPath: String
            let content: String
            let lineCount: Int
        }
        let response = GeneratedFileResponse(
            path: record.outputPath,
            resolvedPath: rendered.path,
            content: rendered.content,
            lineCount: rendered.content.components(separatedBy: .newlines).count
        )
        guard let data = try? JSONEncoder().encode(response) else {
            return .notFound()
        }
        return .ok(body: data)
    }

    private func serveEvaluate(body: Data?) async -> HTTPRouteResponse {
        struct EvalRequest: Decodable {
            let expression: String?
            let eventIndex: Int?
        }
        struct EvalResponse: Encodable {
            let result: String?
            let error: String?
        }
        guard let body,
              let request = try? JSONDecoder().decode(EvalRequest.self, from: body),
              let expr = request.expression, !expr.isEmpty else {
            return .ok(body: "{\"error\":\"Missing expression\"}")
        }
        guard let pipeline, let recorder else {
            return .ok(body: "{\"error\":\"Expression playground requires pipeline and recorder\"}")
        }
        let eventIndex = request.eventIndex ?? max(0, session.events.count - 1)
        let flatVars = await recorder.reconstructState(atEventIndex: eventIndex)
        let data = buildNestedVars(from: flatVars)
        var template = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !template.contains("{{") {
            template = "{{ \(template) }}"
        }
        do {
            if let result = try await pipeline.render(string: template, data: data) {
                let response = EvalResponse(result: result, error: nil)
                let encoded = try JSONEncoder().encode(response)
                return .ok(body: encoded)
            }
            let response = EvalResponse(result: nil, error: "Empty result")
            let encoded = try JSONEncoder().encode(response)
            return .ok(body: encoded)
        } catch {
            let response = EvalResponse(result: nil, error: String(describing: error))
            let encoded = (try? JSONEncoder().encode(response)) ??
                Data("{\"error\":\"\(String(describing: error).replacingOccurrences(of: "\"", with: "\\\""))\"}".utf8)
            return .ok(body: encoded)
        }
    }

    // MARK: - Helpers

    private func sourceFile(for identifier: String) async -> SourceFile? {
        // Gather all source files: session (finalized) + recorder (live)
        var allSourceFiles = session.sourceFiles
        if let recorder = recorder {
            let liveFiles = await recorder.getAllSourceFiles()
            allSourceFiles.append(contentsOf: liveFiles)
        }
        return Self.findSourceFile(identifier: identifier, in: allSourceFiles)
    }
    
    /// Non-isolated helper to search source files without triggering async closure inference.
    private nonisolated static func findSourceFile(identifier: String, in files: [SourceFile]) -> SourceFile? {
        // Exact match
        if let file = files.first(where: { $0.identifier == identifier }) {
            return file
        }
        
        let normalized = identifier.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Partial path match
        let matches = files.filter { file in
            let c = file.identifier.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return c == normalized || c.hasSuffix("/" + normalized) || normalized.hasSuffix("/" + c)
        }
        if matches.count == 1 { return matches[0] }

        // Extension-added match
        let extMatches = files.filter { file in
            let c = file.identifier.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return c == normalized + ".teso" || c == normalized + ".ss"
                || c.hasSuffix("/" + normalized + ".teso") || c.hasSuffix("/" + normalized + ".ss")
        }
        return extMatches.count == 1 ? extMatches[0] : nil
    }

    private func normalizePath(_ path: String) -> String {
        var n = path.replacingOccurrences(of: "\\", with: "/")
        while n.contains("//") { n = n.replacingOccurrences(of: "//", with: "/") }
        if n.count > 1, n.hasSuffix("/") { n.removeLast() }
        return n
    }

    private func generatedFileCandidates(for record: GeneratedFileRecord) -> [String] {
        let outputRoot = URL(fileURLWithPath: session.config.outputPath)
        var candidates: [String] = []
        if record.outputPath.hasPrefix("/") {
            candidates.append(record.outputPath)
        } else {
            candidates.append(outputRoot.appendingPathComponent(record.outputPath).path)
        }
        if !record.workingDir.isEmpty {
            if record.workingDir.hasPrefix("/") {
                let absWD = URL(fileURLWithPath: record.workingDir)
                candidates.append(absWD.appendingPathComponent(record.outputPath).path)
                let relWD = record.workingDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                candidates.append(outputRoot.appendingPathComponent(relWD).appendingPathComponent(record.outputPath).path)
            } else {
                candidates.append(outputRoot.appendingPathComponent(record.workingDir).appendingPathComponent(record.outputPath).path)
            }
        }
        return Array(Set(candidates.map(normalizePath)))
    }

    private func buildNestedVars(from flat: [String: String]) -> [String: Sendable] {
        var result: [String: Sendable] = [:]
        for (key, value) in flat {
            let parts = key.split(separator: ".").map(String.init)
            guard !parts.isEmpty else { continue }
            setNested(result: &result, path: parts, value: value)
        }
        return result
    }

    private func setNested(result: inout [String: Sendable], path: [String], value: String) {
        guard path.count > 1 else {
            result[path[0]] = value
            return
        }
        let key = path[0]
        let rest = Array(path.dropFirst())
        if result[key] == nil { result[key] = [String: Sendable]() }
        var child = result[key] as! [String: Sendable]
        setNested(result: &child, path: rest, value: value)
        result[key] = child
    }
}
