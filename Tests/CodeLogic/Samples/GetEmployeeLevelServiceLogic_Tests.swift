import Testing
@testable import ModelHike

/// `GetEmployeeLevelService` — `IF` / `ELSEIF` / `ELSE`, `DB-RAW` + `SQL` + `PARAMS`, `LET`, `assign`, `return`.
/// SQL uses `EXEC …` (not `SELECT`/`WHERE` as line-leading tokens) to avoid CodeLogic keyword collision; see `Database_Tests.dbRawWithSqlAndParams`.
@Suite struct GetEmployeeLevelServiceLogic_Tests {
    let ctx: LoadContext

    init() async throws {
        self.ctx = LoadContext(config: PipelineConfig())
    }

    @Test func parsesFromFullDSL() async throws {
        let method = try await firstMethod(in: Self.fullModelDSL)
        #expect(await method.name == "getEmployeeLevel")
        #expect(await method.hasLogic == true)

        let logic = try await requireLogic(of: method)
        // db-raw (let absorbed as child), if-with-branches, return
        #expect(logic.statements.count == 3)
        #expect(await logic.statements[0].kind == .dbRaw)
        #expect(await logic.statements[1].kind == .`if`)
        let ifChildren = await logic.statements[1].children
        #expect(ifChildren.count == 4)
        #expect(await ifChildren[1].kind == .elseIf)
        #expect(await ifChildren[2].kind == .elseIf)
        #expect(await ifChildren[3].kind == .`else`)
        #expect(await logic.statements[2].kind == .`return`)

        let lines = await FlatLogicLineData.flatten(logic: logic)
        let kinds = lines.map { $0.kind }
        #expect(kinds.contains(.statement(.dbRaw)))
        #expect(kinds.contains(.statement(.`return`)))
        #expect(kinds.last == .statement(.`return`))

        var sqlOpen: FlatLogicLineData?
        var dbRawClose: FlatLogicLineData?
        for line in lines {
            if sqlOpen == nil, line.kind == .statement(.sql), line.lineType == .open { sqlOpen = line }
            if dbRawClose == nil, line.lineType == .close, line.closingKind == "db-raw" { dbRawClose = line }
        }
        #expect(sqlOpen?.parentKind == "db-raw")
        #expect(sqlOpen?.mergedDbRawResultLetName == "years")
        #expect(dbRawClose?.parentKind == "")
        #expect(dbRawClose?.mergedDbRawResultLetName == "years")
        var letLineKinds: [FlatLogicLineData.LineType] = []
        for line in lines where line.kind == .statement(.`let`) {
            letLineKinds.append(line.lineType)
        }
        #expect(letLineKinds.isEmpty, "LET years = _ is merged into DB-RAW + sql chain")
    }

    @Test func logicParsesStandalone() async throws {
        let logic = try await parseLogicOnly(Self.methodLogicBody)
        // let absorbed into db-raw as child; else/elseif are owned by the if block
        #expect(logic.statements.count == 3)
    }

    // MARK: - Helpers

    private func parse(_ dsl: String) async throws -> ModelSpace {
        try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "GetEmployeeLevelServiceLogic_Tests")
    }

    private func firstMethod(in dsl: String) async throws -> MethodObject {
        let space = try await parse(dsl)
        let types = await space.modules.types
        let obj = try #require(types.first)
        let methods = await obj.methods
        return try #require(methods.first)
    }

    private func requireLogic(of method: MethodObject) async throws -> CodeLogic {
        let logic = await method.logic
        let name = await method.name
        return try #require(logic, "Expected method '\(name)' to have logic")
    }

    private func parseLogicOnly(_ body: String) async throws -> CodeLogic {
        let pInfo = await ParsedInfo.dummy(line: "", identifier: "GetEmployeeLevelServiceLogic_Tests", loadCtx: ctx)
        let logic = try await CodeLogicParser.parse(dslString: body, context: ctx, pInfo: pInfo)
        return try #require(logic)
    }

    /// Setext method body only (what `CodeLogicParser.parse` expects).
    ///
    /// Uses `IF` / `ELSEIF` / `ELSE` at the same depth; the parser folds those branches into the
    /// owning `if` block so `return level` remains the only top-level trailing sibling after the chain.
    ///
    /// SQL uses `EXEC …` so the first token on SQL lines is not a CodeLogic keyword (`SELECT`, `WHERE`, …); see `Database_Tests`.
    private static let methodLogicBody = """
    |> DB-RAW unknown-table
    |> SQL
    |  EXEC dbo.GetEmployeeTenure @emp_id = @emp_id, @years OUTPUT
    |> PARAMS
    |  emp_id = empId
    |  years = years
    |> LET years = _

    |> IF years < 2
    | assign level = "Junior"
    |> ELSEIF years < 5
    | assign level = "Mid-Level"
    |> ELSEIF years < 10
    | assign level = "Senior"
    |> ELSE
    | assign level = "Principal"

    return level
    """

    private static let fullModelDSL = """
    ===
    APIs
    ====
    + HR Services

    === HR Services ===

    GetEmployeeLevelService
    =======================
    getEmployeeLevel(empId: Int) : String
    -------------------------------------
    \(methodLogicBody)
    ---
    """
}
