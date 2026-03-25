import Foundation
import Testing
@testable import ModelHike

@Suite("Enriched DX") struct EnrichedDX_Tests {

    @Test func unknownModifier_includesSuggestionAndAvailableModifiers() async throws {
        let ws = Workspace()

        do {
            _ = try await ws.render(string: "{{ name | lowercas }}", data: ["name": "World"])
            Issue.record("Expected unknown modifier to throw")
        } catch let err as ErrorWithMessage {
            #expect(err.info.contains("'lowercas' not found"))
            #expect(err.info.contains("did you mean 'lowercase'?"))
            #expect(err.info.contains("available modifiers:"))
        } catch {
            Issue.record("Unexpected error type: \(String(describing: error))")
        }
    }

    @Test func unknownVariable_includesSuggestionAndVariablesInScope() async throws {
        let ws = Workspace()

        do {
            _ = try await ws.render(string: "{{ usernme }}", data: ["username": "World"])
            Issue.record("Expected unknown variable to throw")
        } catch let err as ErrorWithMessage {
            #expect(err.info.contains("Variable or property 'usernme' not found"))
            #expect(err.info.contains("did you mean 'username'?"))
            #expect(err.info.contains("variables in scope:"))
        } catch {
            Issue.record("Unexpected error type: \(String(describing: error))")
        }
    }

    @Test func unknownTemplateFunction_includesSuggestionAndAvailableFunctions() async throws {
        let ws = Workspace()
        let sandbox = await ws.newStringSandbox()
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)
        let knownFunction = TemplateFunction(name: "greet", params: ["name"], pInfo: pInfo)
        await sandbox.context.templateFunctions.set("greet", value: knownFunction)

        do {
            var stmt = FunctionCallStmt(pInfo)
            let didMatch = try stmt.matchLine(line: "call grete(name: username)")
            #expect(didMatch)
            _ = try await stmt.execute(with: sandbox.context)
            Issue.record("Expected unknown template function to throw")
        } catch let err as ErrorWithMessage {
            #expect(err.info.contains("Template function 'grete' not found"))
            #expect(err.info.contains("did you mean 'greet'?"))
            #expect(err.info.contains("available template functions:"))
        } catch {
            Issue.record("Unexpected error type: \(String(describing: error))")
        }
    }

    @Test func unknownInfixOperator_includesSuggestionAndAvailableOperators() async throws {
        let ws = Workspace()
        let sandbox = await ws.newStringSandbox()
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)
        let evaluator = RegularExpressionEvaluator()
        await sandbox.context.variables.set("isAdmin", value: true)
        await sandbox.context.variables.set("isOwner", value: false)

        do {
            _ = try await evaluator.evaluate(expression: "isAdmin orr isOwner", pInfo: pInfo)
            Issue.record("Expected unknown operator to throw")
        } catch let err as ErrorWithMessage {
            #expect(err.info.contains("Operator 'orr' not found"))
            #expect(err.info.contains("did you mean 'or'?"))
            #expect(err.info.contains("available operators:"))
        } catch {
            Issue.record("Unexpected error type: \(String(describing: error))")
        }
    }

    @Test func noArgModifier_calledWithArgs_hasExplicitGuidance() async throws {
        let ws = Workspace()

        do {
            _ = try await ws.render(string: "{{ name | lowercase(\"x\") }}", data: ["name": "World"])
            Issue.record("Expected invalid modifier syntax to throw")
        } catch let err as ErrorWithMessage {
            #expect(err.info.contains("'lowercase' does not accept arguments"))
            #expect(err.info.contains("| lowercase"))
        } catch {
            Issue.record("Unexpected error type: \(String(describing: error))")
        }
    }

    @Test func argsRequiredModifier_calledWithoutArgs_hasExplicitGuidance() async throws {
        let ws = Workspace()
        let sandbox = await CodeGenerationSandbox(model: ws.context.model, config: await ws.config)
        let modifiers = try await InlineBlueprint(name: "test") {
            InlineModifier("wrap", contents: """
                ---
                params: prefix
                ---
                {{ prefix }}{{ value }}
                """)
        }.modifiers(from: sandbox)

        do {
            _ = try await ws.render(string: "{{ name | wrap }}", data: ["name": "World"], modifiers: modifiers)
            Issue.record("Expected missing modifier arguments to throw")
        } catch let err as ErrorWithMessage {
            #expect(err.info.contains("'wrap' requires arguments"))
            #expect(err.info.contains("wrap(arg1"))
        } catch {
            Issue.record("Unexpected error type: \(String(describing: error))")
        }
    }

    @Test func typeRestrictedModifier_wrongType_reportsExpectedVsFound() async throws {
        let ws = Workspace()
        let sandbox = await CodeGenerationSandbox(model: ws.context.model, config: await ws.config)
        let modifiers = try await InlineBlueprint(name: "test") {
            InlineModifier("stringOnly", contents: """
                ---
                type: String
                ---
                {{ value }}
                """)
        }.modifiers(from: sandbox)

        do {
            _ = try await ws.render(string: "{{ num | stringOnly }}", data: ["num": 42.0], modifiers: modifiers)
            Issue.record("Expected wrong modifier type to throw")
        } catch let err as ErrorWithMessage {
            #expect(err.info.contains("Modifier 'stringOnly' cannot be applied"))
            #expect(err.info.contains("type 'Double'"))
            #expect(err.info.contains("Expected a compatible input type"))
        } catch {
            Issue.record("Unexpected error type: \(String(describing: error))")
        }
    }

    @Test func infixOperator_wrongLhsType_reportsPreciseMessage() async throws {
        let ws = Workspace()
        let sandbox = await ws.newStringSandbox()
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)
        let op = InfixOperator<String, String, Bool>(name: "contains") { lhs, rhs in
            lhs.contains(rhs)
        }

        do {
            _ = try op.applyTo(lhs: true, rhs: "x", pInfo: pInfo)
            Issue.record("Expected wrong operator lhs type to throw")
        } catch let err as ErrorWithMessage {
            #expect(err.info.contains("Operator 'contains' cannot be applied"))
            #expect(err.info.contains("left-hand side has unexpected type"))
        } catch {
            Issue.record("Unexpected error type: \(String(describing: error))")
        }
    }

    @Test func diagnosticEvent_encodesSeverityCodeSourceAndSuggestions() async throws {
        var config = PipelineConfig()
        config.flags.printDiagnosticsToStdout = false
        let recorder = DefaultDebugRecorder()
        config.debugRecorder = recorder

        let ws = Workspace()
        await ws.config(config)

        let sandbox = await ws.newStringSandbox()
        let pInfo = await ParsedInfo.dummy(line: ":if usernme", identifier: "main.ss", generationCtx: sandbox.context)
        await sandbox.context.debugLog.recordDiagnostic(
            .warning,
            code: "W201",
            "Condition 'usernme' resolved to nil — treating as false.",
            pInfo: pInfo,
            suggestions: [
                DiagnosticSuggestion(
                    kind: .didYouMean,
                    message: "did you mean 'username'?",
                    replacement: "username",
                    options: ["username"]
                ),
                DiagnosticSuggestion(
                    kind: .availableOptions,
                    message: "variables in scope: username",
                    options: ["username"]
                )
            ]
        )

        // ContextDebugLog records via Task, so give the recorder a moment to capture the event.
        try await Task.sleep(for: .milliseconds(20))

        let session = await recorder.session(config: config)
        let envelope = try #require(session.events.first(where: { envelope in
            if case .diagnostic = envelope.event { return true }
            return false
        }))

        switch envelope.event {
        case .diagnostic(let severity, let code, let message, let source, let suggestions):
            var hasDidYouMeanReplacement = false
            for suggestion in suggestions {
                if suggestion.kind == .didYouMean && suggestion.replacement == "username" {
                    hasDidYouMeanReplacement = true
                    break
                }
            }
            #expect(severity == .warning)
            #expect(code == "W201")
            #expect(message.contains("resolved to nil"))
            #expect(source.fileIdentifier == "main.ss")
            #expect(suggestions.contains(where: { $0.message.contains("did you mean 'username'?") }))
            #expect(hasDidYouMeanReplacement)
        default:
            Issue.record("Expected diagnostic event payload")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let event = try #require(json["event"] as? [String: Any])
        let diagnostic = try #require(event["diagnostic"] as? [String: Any])
        let source = try #require(diagnostic["source"] as? [String: Any])
        let suggestions = try #require(diagnostic["suggestions"] as? [[String: Any]])

        #expect(diagnostic["severity"] as? String == "warning")
        #expect(diagnostic["code"] as? String == "W201")
        #expect((diagnostic["message"] as? String)?.contains("resolved to nil") == true)
        #expect(source["fileIdentifier"] as? String == "main.ss")
        #expect((source["lineNo"] as? Int) == -1)
        #expect(suggestions.contains(where: { $0["kind"] as? String == "didYouMean" }))
        #expect(suggestions.contains(where: { $0["message"] as? String == "did you mean 'username'?" }))
        #expect(suggestions.contains(where: { $0["replacement"] as? String == "username" }))
    }

    @Test func templateAndEvaluationErrors_exposeStableCodes() async throws {
        let ws = Workspace()
        let sandbox = await ws.newStringSandbox()
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)

        let errors: [(any ErrorWithMessage, String)] = [
            (TemplateSoup_ParsingError.invalidFrontMatter("bad", pInfo), "E201"),
            (TemplateSoup_ParsingError.modifierNotFound("missing", pInfo), "E205"),
            (TemplateSoup_ParsingError.variableOrPropertyNotFound("missing", pInfo), "E212"),
            (TemplateSoup_ParsingError.templateFunctionNotFound("missing", pInfo), "E218"),
            (TemplateSoup_EvaluationError.unIdentifiedStmt(pInfo), "E302"),
            (TemplateSoup_EvaluationError.invalidFileSystemPath(
                operation: "copy-file",
                argument: "as",
                expression: "targetPath",
                actualType: "Bool",
                pInfo
            ), "E304"),
            (TemplateSoup_EvaluationError.templateDoesNotExist("user.teso", pInfo), "E306"),
            (TemplateSoup_EvaluationError.nonSendableValueFound("closure", pInfo), "E311"),
        ]

        for (error, code) in errors {
            #expect(error.code == code)
            #expect(error.infoWithCode.hasPrefix("[\(code)] "))
        }
    }

    @Test func wrapperAndModelErrors_exposeStableCodesAndPreserveNestedCodes() async throws {
        let ws = Workspace()
        let sandbox = await ws.newStringSandbox()
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)

        let modelErrors: [(any ErrorWithMessage, String)] = [
            (Model_ParsingError.objectTypeNotFound("type missing", pInfo), "E601"),
            (Model_ParsingError.invalidMapping("a ->", pInfo), "E604"),
            (Model_ParsingError.invalidAnnotationLine(pInfo), "E615"),
            (Model_ParsingError.invalidApiLine(pInfo), "E617"),
        ]

        for (error, code) in modelErrors {
            #expect(error.code == code)
            #expect(error.infoWithCode.hasPrefix("[\(code)] "))
        }

        let nestedParsing = ParsingError.invalidLine(pInfo, TemplateSoup_ParsingError.modifierNotFound("missing", pInfo))
        #expect(nestedParsing.code == "E205")
        #expect(nestedParsing.infoWithCode.hasPrefix("[E205] "))

        let plainParsing = ParsingError.invalidLineWithoutErr("plain parse failure", pInfo)
        #expect(plainParsing.code == "E402")
        #expect(plainParsing.infoWithCode.hasPrefix("[E402] "))

        let nestedEvaluation = EvaluationError.templateDoesNotExist(
            pInfo,
            TemplateSoup_EvaluationError.templateDoesNotExist("user.teso", pInfo)
        )
        #expect(nestedEvaluation.code == "E306")
        #expect(nestedEvaluation.infoWithCode.hasPrefix("[E306] "))

        let genericEvaluation = EvaluationError.failedWriteOperation("write failed", pInfo)
        #expect(genericEvaluation.code == "E504")
        #expect(genericEvaluation.infoWithCode.hasPrefix("[E504] "))
    }

    @Test func errorEvent_encodesStructuredErrorCode() throws {
        let event = DebugEvent.error(
            category: "template-evaluation",
            code: "E304",
            message: "Filesystem error in copy-file: 'as' path 'targetPath' expected String, got Bool",
            source: SourceLocation(fileIdentifier: "main.ss", lineNo: 12, lineContent: "copy-file a as b", level: 0),
            callStack: []
        )
        let envelope = DebugEventEnvelope(sequenceNo: 1, timestamp: Date(), containerName: "APIs", event: event)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let eventObj = try #require(json["event"] as? [String: Any])
        let errorObj = try #require(eventObj["error"] as? [String: Any])

        #expect(errorObj["category"] as? String == "template-evaluation")
        #expect(errorObj["code"] as? String == "E304")
        #expect((errorObj["message"] as? String)?.contains("Filesystem error") == true)
    }
}
