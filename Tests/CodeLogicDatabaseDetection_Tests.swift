import Testing
@testable import ModelHike

@Suite struct CodeLogicDatabaseDetection_Tests {

    @Test func detectsDbRaw() async throws {
        let logic = try await parse("|> DB-RAW src")
        #expect(await logic.containsDatabaseStatement())
    }

    @Test func detectsNestedSqlUnderDbRaw() async throws {
        let logic = try await parse("""
            |> DB-RAW src
            |> SQL
            |  EXEC foo
            """)
        #expect(await logic.containsDatabaseStatement())
    }

    @Test func returnOnlyIsNotDb() async throws {
        let logic = try await parse("return 1")
        #expect(await !logic.containsDatabaseStatement())
        #expect(await !logic.containsDataAccessStatement())
        #expect(await !logic.containsTransactionControlStatement())
    }

    @Test func dataAccessVsTransactionControl() async throws {
        let txOnly = try await parse("""
            |> TRANSACTION
            | commit
            """)
        #expect(await txOnly.containsDatabaseStatement())
        #expect(await !txOnly.containsDataAccessStatement())
        #expect(await txOnly.containsTransactionControlStatement())

        let dataOnly = try await parse("|> DB-RAW x")
        #expect(await dataOnly.containsDatabaseStatement())
        #expect(await dataOnly.containsDataAccessStatement())
        #expect(await !dataOnly.containsTransactionControlStatement())
    }

    private func parse(_ dslString: String) async throws -> CodeLogic {
        let ctx = LoadContext(config: PipelineConfig())
        let pInfo = await ParsedInfo.dummy(line: "", identifier: "CodeLogicDatabaseDetection_Tests", loadCtx: ctx)
        let logic = try await CodeLogicParser.parse(dslString: dslString, context: ctx, pInfo: pInfo)
        return try #require(logic)
    }
}
