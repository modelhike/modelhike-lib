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
        #expect(lines[2].depth == 2)
        #expect(lines[3].depth == 3)
        #expect(lines[4].depth == 1)
        #expect(lines[4].lineType == .close)
        #expect(lines[4].closingKind == "if")
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

    @Test func blockOwnsBranchKindsOnlyForItsOwnBranches() {
        #expect(CodeLogicStmt.blockOwnership(for: .if).branchKinds.contains(.else))
        #expect(CodeLogicStmt.blockOwnership(for: .if).branchKinds.contains(.elseIf))
        #expect(CodeLogicStmt.blockOwnership(for: .try).branchKinds.contains(.catch))
        #expect(CodeLogicStmt.blockOwnership(for: .try).branchKinds.contains(.finally))
        #expect(CodeLogicStmt.blockOwnership(for: .switch).branchKinds.contains(.case))
        #expect(CodeLogicStmt.blockOwnership(for: .switch).branchKinds.contains(.default))
        #expect(CodeLogicStmt.blockOwnership(for: .dbRaw).branchKinds.isEmpty)
        #expect(CodeLogicStmt.blockOwnership(for: .http).branchKinds.isEmpty)
        #expect(CodeLogicStmt.blockOwnership(for: .grpc).branchKinds.isEmpty)
        #expect(CodeLogicStmt.blockOwnership(for: .notify).branchKinds.isEmpty)
        #expect(!CodeLogicStmt.blockOwnership(for: .case).branchKinds.contains(.default))
        #expect(!CodeLogicStmt.blockOwnership(for: .dbRaw).branchKinds.contains(.case))
        #expect(!CodeLogicStmt.blockOwnership(for: .http).branchKinds.contains(.headers))
        #expect(!CodeLogicStmt.blockOwnership(for: .if).branchKinds.contains(.return))
    }

    @Test func partsStayGroupedWithTheirParentBlock() {
        #expect(CodeLogicStmt.blockOwnership(for: .db).partKinds.contains(.where))
        #expect(CodeLogicStmt.blockOwnership(for: .dbRaw).partKinds.contains(.sql))
        #expect(CodeLogicStmt.blockOwnership(for: .http).partKinds.contains(.headers))
        #expect(CodeLogicStmt.blockOwnership(for: .grpc).partKinds.contains(.payload))
        #expect(CodeLogicStmt.blockOwnership(for: .notify).partKinds.contains(.subject))
        #expect(CodeLogicStmt.blockOwnership(for: .publish).partKinds.contains(.metadata))
        #expect(!CodeLogicStmt.blockOwnership(for: .switch).partKinds.contains(.case))
        #expect(!CodeLogicStmt.blockOwnership(for: .if).partKinds.contains(.else))
    }

    @Test func flattenSwitchClausesStayWithinSwitchBlock() async throws {
        let logic = try await parseLogic("""
            |> SWITCH status
            |> CASE "active"
            | return true
            |> DEFAULT
            | return false
            """)
        let lines = await FlatLogicLineData.flatten(logic: logic)
        let kinds = lines.map { $0.kind }
        let types = lines.map { $0.lineType }
        let depths = lines.map { $0.depth }

        #expect(kinds == [
            .statement(.switch), .statement(.case), .statement(.return),
            .statement(.default), .statement(.return), .close,
        ])
        #expect(types == [.open, .open, .leaf, .open, .leaf, .close])
        #expect(depths == [1, 2, 3, 2, 3, 1])
        #expect(lines[5].closingKind == "switch")
    }

    private func parseLogic(_ dslString: String) async throws -> CodeLogic {
        let ctx = LoadContext(config: PipelineConfig())
        let pInfo = await ParsedInfo.dummy(line: "", identifier: "FlatLogicLineData_Tests", loadCtx: ctx)
        let logic = try await CodeLogicParser.parse(dslString: dslString, context: ctx, pInfo: pInfo)
        return try #require(logic, "Expected CodeLogicParser to return non-nil CodeLogic")
    }
}
