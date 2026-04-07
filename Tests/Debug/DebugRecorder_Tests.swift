//
//  DebugRecorder_Tests.swift
//  ModelHikeTests
//

import Foundation
import Testing
@testable import ModelHike

@Suite struct DebugRecorder_Tests {

    @Test func recordEventsAndReconstructState() async throws {
        let recorder = DefaultDebugRecorder()
        await recorder.recordEvent(.phaseStarted(name: "Discover", timestamp: Date()))
        await recorder.captureBaseSnapshot(label: "phase", variables: ["a": "1", "b": "2"])
        await recorder.recordEvent(.phaseCompleted(name: "Discover", duration: 0.1))
        await recorder.captureDelta(eventIndex: 2, variable: "b", oldValue: "2", newValue: "3")

        let varsAt0 = await recorder.reconstructState(atEventIndex: 0)
        #expect(varsAt0.isEmpty)

        let varsAt1 = await recorder.reconstructState(atEventIndex: 1)
        #expect(varsAt1["a"] == "1")
        #expect(varsAt1["b"] == "2")

        let varsAt2 = await recorder.reconstructState(atEventIndex: 2)
        #expect(varsAt2["a"] == "1")
        #expect(varsAt2["b"] == "3")
    }

    @Test func addGeneratedFileAndSession() async throws {
        let recorder = DefaultDebugRecorder()
        await recorder.recordEvent(.fileGenerated(outputPath: "out/foo.ts", templateName: "entity.teso", objectName: "User", source: SourceLocation(fileIdentifier: "main.ss", lineNo: 10, lineContent: "render-file", level: 0)))
        await recorder.addGeneratedFile(outputPath: "out/foo.ts", templateName: "entity.teso", objectName: "User", workingDir: "/apps/user/")

        let config = PipelineConfig()
        let session = await recorder.session(config: config)
        #expect(session.files.count == 1)
        #expect(session.files[0].outputPath == "out/foo.ts")
        #expect(session.files[0].relativeOutputPath == "apps/user/out/foo.ts")
        #expect(session.files[0].templateName == "entity.teso")
        #expect(session.files[0].objectName == "User")
    }

    @Test func sessionNormalizesGeneratedFilePathsRelativeToOutputRoot() async throws {
        let recorder = DefaultDebugRecorder()
        let outputRoot = "/tmp/output"

        await recorder.addGeneratedFile(
            outputPath: "package.json",
            templateName: nil,
            objectName: nil,
            workingDir: "/tmp/output/APIs"
        )
        await recorder.addGeneratedFile(
            outputPath: "controller.ts",
            templateName: "entity.teso",
            objectName: "Subscription",
            workingDir: "/tmp/output/APIs/apps/billing/src/subscription"
        )
        await recorder.addGeneratedFile(
            outputPath: "/tmp/output/APIs/README.md",
            templateName: nil,
            objectName: nil,
            workingDir: ""
        )

        var config = PipelineConfig()
        config.output = LocalFolder(path: LocalPath(outputRoot))

        let session = await recorder.session(config: config)
        var relativePaths: [String] = []
        for file in session.files {
            relativePaths.append(file.relativeOutputPath)
        }
        #expect(relativePaths == [
            "APIs/package.json",
            "APIs/apps/billing/src/subscription/controller.ts",
            "APIs/README.md",
        ])
    }

    @Test func registerSourceFile() async throws {
        let recorder = DefaultDebugRecorder()
        let file = SourceFile(identifier: "main.ss", fullPath: "/path/main.ss", content: "render-file x\nend", fileType: .soupyScript)
        await recorder.registerSourceFile(file)

        let config = PipelineConfig()
        let session = await recorder.session(config: config)
        #expect(session.sourceFiles.count == 1)
        #expect(session.sourceFiles[0].identifier == "main.ss")
        #expect(session.sourceFiles[0].content.contains("render-file"))
    }
}
