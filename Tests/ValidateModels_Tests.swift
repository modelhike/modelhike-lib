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
        var codes: [String] = []
        for envelope in events {
            if case .diagnostic(_, let code, _, _, _) = envelope.event {
                if let code {
                    codes.append(code)
                }
            }
        }

        #expect(codes.contains("W301"))
    }
}
