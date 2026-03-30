import Testing
@testable import ModelHike

@Suite struct FlatLogicLineData_Tests {

    @Test func flattenEmptyLogic() async {
        let lines = await FlatLogicLineData.flatten(logic: CodeLogic())
        #expect(lines.isEmpty)
    }

    @Test func flattenSingleReturn() async throws {
        let logic = try await parseLogic("return amount * 2")
        let lines = await FlatLogicLineData.flatten(logic: logic)
        #expect(lines.count == 1)
        #expect(lines[0].kind == .statement(.return))
        #expect(lines[0].lineType == .leaf)
        #expect(lines[0].depth == 0)
        #expect(lines[0].expression == "amount * 2")
    }

    @Test func flattenIfElseSuppressesCloseBeforeElse() async throws {
        let logic = try await parseLogic("""
            |> IF percent <= 0
            |return amount
            |> ELSE
            |return amount * 0.9
            """)
        let lines = await FlatLogicLineData.flatten(logic: logic)
        let kinds = lines.map { $0.kind }
        let types = lines.map { $0.lineType }
        #expect(kinds == [
            .statement(.if), .statement(.return), .statement(.else), .statement(.return), .close,
        ])
        #expect(types == [.open, .leaf, .open, .leaf, .close])
        #expect(lines[0].depth == 0)
        #expect(lines[1].depth == 1)
        #expect(lines[2].depth == 0)
        #expect(lines[3].depth == 1)
        #expect(lines[4].depth == 0)
        #expect(lines[4].lineType == .close)
    }

    @Test func isChainedAfter() {
        #expect(FlatLogicLineData.isChainedAfter(.else, previous: .if))
        #expect(FlatLogicLineData.isChainedAfter(.elseIf, previous: .if))
        #expect(FlatLogicLineData.isChainedAfter(.catch, previous: .try))
        #expect(FlatLogicLineData.isChainedAfter(.finally, previous: .catch))
        #expect(!FlatLogicLineData.isChainedAfter(.return, previous: .if))
    }

    private func parseLogic(_ dslString: String) async throws -> CodeLogic {
        let logic = await CodeLogicParser.parse(dslString: dslString)
        return try #require(logic, "Expected CodeLogicParser to return non-nil CodeLogic")
    }
}
