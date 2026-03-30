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
        // db-raw, let, if, elseif, elseif, else, return
        #expect(logic.statements.count == 7)
        #expect(await logic.statements[0].kind == .dbRaw)
        #expect(await logic.statements[1].kind == .`let`)
        #expect(await logic.statements[2].kind == .`if`)
        #expect(await logic.statements[3].kind == .elseIf)
        #expect(await logic.statements[4].kind == .elseIf)
        #expect(await logic.statements[5].kind == .`else`)
        #expect(await logic.statements[6].kind == .`return`)

        let lines = await FlatLogicLineData.flatten(logic: logic)
        let kinds = lines.map { $0.kind }
        #expect(kinds.contains(.statement(.dbRaw)))
        #expect(kinds.contains(.statement(.`return`)))
        #expect(kinds.last == .statement(.`return`))
    }

    @Test func logicParsesStandalone() async throws {
        let logic = try await parseLogicOnly(Self.methodLogicBody)
        #expect(logic.statements.count == 7)
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
        let logic = await CodeLogicParser.parse(dslString: body)
        return try #require(logic)
    }

    /// Setext method body only (what `CodeLogicParser.parse` expects).
    ///
    /// Uses `IF` / `ELSEIF` / `ELSE` at the same depth so `return level` is a top-level sibling.
    /// (Deeply nested `ELSE` + `IF` + bare `return` can attach `return` to the outer `else` in the current tree builder.)
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
