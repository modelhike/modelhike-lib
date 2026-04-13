import Foundation
import Testing
@testable import ModelHike

@Suite("Validate models") struct ValidateModels_Tests {
    @Test func unresolvedCustomType_emitsW301() async throws {
        let recorder = DefaultDebugRecorder()
        let pipeline = Pipeline {
            LoadModelsPass()
            HydrateModelsPass()
            PassDownAndProcessAnnotationsPass()
            ValidateModelsPass()
        }

        var config = PipelineConfig()
        config.debugRecorder = recorder
        config.flags.printDiagnosticsToStdout = false

        let context = await pipeline.ws.context
        let loader = InlineModelLoader(with: context) {
            InlineModel {
                """
                ===
                APIs
                ====
                + Registry Management

                === Registry Management ===

                Subscription
                ============
                * _id: String
                * owner: CustomerProfile
                """
            }
        }
        config.modelSource = .inline(loader)

        _ = try await pipeline.run(using: config)

        await context.debugLog.drainRecorder()
        let session = await recorder.session(config: config)
        let events = session.events
        var codes: [DiagnosticErrorCode] = []
        for envelope in events {
            if case .diagnostic(_, let code, _, _, _) = envelope.event {
                if let code {
                    codes.append(code)
                }
            }
        }

        #expect(codes.contains(.w301))
    }

    @Test func validationWarnings_preserveParsedSourceLocations() async throws {
        let recorder = DefaultDebugRecorder()
        let pipeline = Pipeline {
            LoadModelsPass()
            HydrateModelsPass()
            PassDownAndProcessAnnotationsPass()
            ValidateModelsPass()
        }

        var config = PipelineConfig()
        config.debugRecorder = recorder
        config.flags.printDiagnosticsToStdout = false

        let context = await pipeline.ws.context
        let loader = InlineModelLoader(with: context) {
            InlineModel(identifier: "warnings.modelhike") {
                """
                ===
                APIs
                ====
                + Missing Module
                + Registry Management

                === Registry Management ===

                Subscription
                ============
                * _id: String
                * owner: CustomerProfile
                * ref: String = @missingExpr
                * name: String
                * name: String
                ~ ping
                ~ ping

                Subscription
                ============
                * _id: String
                """
            }
        }
        config.modelSource = .inline(loader)

        _ = try await pipeline.run(using: config)

        await context.debugLog.drainRecorder()
        let session = await recorder.session(config: config)
        var locations: [DiagnosticErrorCode: ModelHike.SourceLocation] = [:]
        for envelope in session.events {
            if case .diagnostic(_, let code, _, let source, _) = envelope.event, let code {
                locations[code] = source
            }
        }

        #expect(locations[.w301]?.fileIdentifier == "warnings.modelhike")
        #expect(locations[.w301]?.lineNo == 12)
        #expect(locations[.w302]?.fileIdentifier == "warnings.modelhike")
        #expect(locations[.w302]?.lineNo == 13)
        #expect(locations[.w303]?.fileIdentifier == "warnings.modelhike")
        #expect(locations[.w303]?.lineNo == 4)
        #expect(locations[.w304]?.fileIdentifier == "warnings.modelhike")
        #expect(locations[.w304]?.lineNo == 19)
        #expect(locations[.w305]?.fileIdentifier == "warnings.modelhike")
        #expect(locations[.w305]?.lineNo == 15)
        #expect(locations[.w306]?.fileIdentifier == "warnings.modelhike")
        #expect(locations[.w306]?.lineNo == 17)
    }

    @Test func inlineModelIdentifier_isPreservedInParseErrors() async throws {
        let recorder = DefaultDebugRecorder()
        let pipeline = Pipeline {
            LoadModelsPass()
        }

        var config = PipelineConfig()
        config.debugRecorder = recorder
        config.flags.printDiagnosticsToStdout = false

        let context = await pipeline.ws.context
        let loader = InlineModelLoader(with: context) {
            InlineModel(identifier: "broken.modelhike") {
                """
                ===
                APIs
                ====
                + Registry Management

                === Registry Management ===

                Subscription
                ============
                * _id: String
                * owner CustomerProfile
                """
            }
        }
        config.modelSource = .inline(loader)

        let succeeded = try await pipeline.run(using: config)

        #expect(succeeded == false)

        await context.debugLog.drainRecorder()
        let session = await recorder.session(config: config)
        var errorSources: [ModelHike.SourceLocation] = []
        for envelope in session.events {
            if case .error(_, _, _, let source, _) = envelope.event {
                errorSources.append(source)
            }
        }

        #expect(errorSources.contains(where: { $0.fileIdentifier == "broken.modelhike" && $0.lineNo > 0 }))
    }
}
