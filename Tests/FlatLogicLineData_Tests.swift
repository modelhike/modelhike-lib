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
        #expect(lines[0].depth == 1)
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
        #expect(lines[0].depth == 1)
        #expect(lines[1].depth == 2)
        #expect(lines[2].depth == 1)
        #expect(lines[3].depth == 2)
        #expect(lines[4].depth == 1)
        #expect(lines[4].lineType == .close)
        #expect(lines[4].closingKind == "else")
        #expect(lines[4].parentKind == "")
    }

    @Test func closingKindAndParentKindForDbRaw() async throws {
        let logic = try await parseLogic("""
            |> DB-RAW src
            |> SQL
            |  EXEC foo
            |> PARAMS
            |  a = b
            """)
        let lines = await FlatLogicLineData.flatten(logic: logic)
        var sqlOpen: FlatLogicLineData?
        var unknownLeaf: FlatLogicLineData?
        var assignInParams: FlatLogicLineData?
        var sqlClose: FlatLogicLineData?
        for line in lines {
            if sqlOpen == nil, line.kind == .statement(.sql), line.lineType == .open { sqlOpen = line }
            if unknownLeaf == nil, line.kind == .statement(.unknown), line.lineType == .leaf { unknownLeaf = line }
            if assignInParams == nil, line.kind == .statement(.assign), line.lineType == .leaf { assignInParams = line }
            if sqlClose == nil, line.lineType == .close, line.closingKind == "sql" { sqlClose = line }
        }
        #expect(sqlOpen?.parentKind == "db-raw")
        #expect(unknownLeaf?.parentKind == "sql")
        #expect(assignInParams?.parentKind == "params")
        #expect(sqlClose?.parentKind == "db-raw")
        var dbRawClose: FlatLogicLineData?
        for line in lines where line.lineType == .close && line.closingKind == "db-raw" {
            dbRawClose = line
            break
        }
        #expect(dbRawClose?.depth == 1)
        #expect(String(repeating: "    ", count: (dbRawClose?.depth ?? 0) + 2) == "            ")
    }

    @Test func isChainedAfter() {
        #expect(FlatLogicLineData.isChainedAfter(.else, previous: .if))
        #expect(FlatLogicLineData.isChainedAfter(.elseIf, previous: .if))
        #expect(FlatLogicLineData.isChainedAfter(.catch, previous: .try))
        #expect(FlatLogicLineData.isChainedAfter(.finally, previous: .catch))
        #expect(!FlatLogicLineData.isChainedAfter(.return, previous: .if))
    }

    private func parseLogic(_ dslString: String) async throws -> CodeLogic {
        let ctx = LoadContext(config: PipelineConfig())
        let pInfo = await ParsedInfo.dummy(line: "", identifier: "FlatLogicLineData_Tests", loadCtx: ctx)
        let logic = try await CodeLogicParser.parse(dslString: dslString, context: ctx, pInfo: pInfo)
        return try #require(logic, "Expected CodeLogicParser to return non-nil CodeLogic")
    }
}
