import Testing
@testable import ModelHike

@Suite("NOTIFY / PUBLISH statements") struct CodeLogicNotifyPublish_Tests {

    private func parse(_ dslString: String) async throws -> CodeLogic {
        let ctx = LoadContext(config: PipelineConfig())
        let pInfo = await ParsedInfo.dummy(line: "", identifier: "CodeLogicNotifyPublish_Tests", loadCtx: ctx)
        let logic = try await CodeLogicParser.parse(dslString: dslString, context: ctx, pInfo: pInfo)
        return try #require(logic)
    }

    @Test func notifyEmailWithToSubjectBody() async throws {
        let logic = try await parse("""
            |> NOTIFY EMAIL admin@example.com
            |> TO ops@example.com
            |> SUBJECT Alert
            |> BODY
            |  Something went wrong
            |> LET _ = _
            """)

        #expect(logic.statements.count == 1)
        let stmt = logic.statements[0]
        #expect(await stmt.kind == .notify)

        guard case .notify(let node) = await stmt.node else {
            Issue.record("Expected .notify")
            return
        }
        #expect(node.notificationType == "EMAIL")
        #expect(node.recipient == "admin@example.com")

        let ch = await stmt.children
        #expect(ch.count == 4)
        #expect(await ch[0].kind == .to)
        #expect(await ch[1].kind == .subject)
        #expect(await ch[2].kind == .body)
        #expect(await ch[3].kind == .`let`)
    }

    @Test func notifyPushWithTitleBodyData() async throws {
        let logic = try await parse("""
            |> NOTIFY PUSH customer-42
            |> TITLE Hello
            |> BODY Tap to open
            |> DATA
            |  deeplink = app://orders/1
            """)

        let stmt = logic.statements[0]
        guard case .notify(let node) = await stmt.node else {
            Issue.record("Expected .notify")
            return
        }
        #expect(node.notificationType == "PUSH")
        #expect(node.recipient == "customer-42")

        let kids = await stmt.children
        var kinds: [CodeLogicStmtKind] = []
        for s in kids {
            kinds.append(await s.kind)
        }
        #expect(kinds.contains(.title))
        #expect(kinds.contains(.body))
        #expect(kinds.contains(.data))
    }

    @Test func publishEventWithPayloadOnly() async throws {
        let logic = try await parse("""
            |> PUBLISH OrderCompleted
            |> PAYLOAD
            |  orderId = order.id
            """)

        let stmt = logic.statements[0]
        guard case .publish(let node) = await stmt.node else {
            Issue.record("Expected .publish")
            return
        }
        #expect(node.eventName == "OrderCompleted")
        #expect(node.channel == nil)
    }

    @Test func publishEventWithToChannel() async throws {
        let logic = try await parse("""
            |> PUBLISH OrderCancelled TO order-events
            |> PAYLOAD
            |  id = order.id
            """)

        let stmt = logic.statements[0]
        guard case .publish(let node) = await stmt.node else {
            Issue.record("Expected .publish")
            return
        }
        #expect(node.eventName == "OrderCancelled")
        #expect(node.channel == "order-events")
    }
}
