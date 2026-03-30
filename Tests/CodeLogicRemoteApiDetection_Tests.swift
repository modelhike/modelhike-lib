import Testing
@testable import ModelHike

@Suite struct CodeLogicRemoteApiDetection_Tests {

    @Test func detectsHttp() async throws {
        let logic = try await parse("""
            |> HTTP GET https://api.example.com/x
            |> LET r = _
            """)
        #expect(await logic.containsHttpClientStatement())
        #expect(await !logic.containsGrpcClientStatement())
        #expect(await !logic.containsWebSocketStatement())
    }

    @Test func detectsGrpc() async throws {
        let logic = try await parse("""
            |> GRPC com.example.Svc/Method
            |> PAYLOAD
            |  x = 1
            """)
        #expect(await logic.containsGrpcClientStatement())
        #expect(await !logic.containsHttpClientStatement())
    }

    @Test func detectsWebSocketStatement() async throws {
        let logic = try await parse("""
            |> WEBSOCKET GET wss://echo.example.com/socket
            |> LET r = _
            """)
        #expect(await logic.containsWebSocketStatement())
        #expect(await !logic.containsHttpClientStatement())
    }

    @Test func httpWithWssUrlIsHttpOnlyNotWebSocketStmt() async throws {
        let logic = try await parse("|> HTTP GET wss://echo.example.com/socket")
        #expect(await logic.containsHttpClientStatement())
        #expect(await !logic.containsWebSocketStatement())
    }

    private func parse(_ dslString: String) async throws -> CodeLogic {
        let ctx = LoadContext(config: PipelineConfig())
        let pInfo = await ParsedInfo.dummy(line: "", identifier: "CodeLogicRemoteApiDetection_Tests", loadCtx: ctx)
        let logic = try await CodeLogicParser.parse(dslString: dslString, context: ctx, pInfo: pInfo)
        return try #require(logic)
    }
}
