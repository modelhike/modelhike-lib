import Testing
@testable import ModelHike

@Suite struct GenerateCodePass_Tests {
    @Test func blueprintNameComesFromContainerTag() async throws {
        let (container, sandbox) = try await parseFirstContainerWithSandbox("""
            ===
            APIs #blueprint(api-springboot-monorepo)
            ===
            + HR

            === HR ===

            Employee
            ========
            ** employeeId : Id
            """)
        let pass = GenerateCodePass()
        let pInfo = await ParsedInfo.dummyForAppState(with: sandbox.context)

        let blueprintName = await pass.blueprintName(for: container, sandbox: sandbox, pInfo: pInfo)

        #expect(blueprintName == "api-springboot-monorepo")
    }

    @Test func missingBlueprintTagReturnsNil() async throws {
        let (container, sandbox) = try await parseFirstContainerWithSandbox("""
            ===
            APIs #blueprint
            ===
            + HR

            === HR ===

            Employee
            ========
            ** employeeId : Id
            """)
        let pass = GenerateCodePass()
        let pInfo = await ParsedInfo.dummyForAppState(with: sandbox.context)

        let blueprintName = await pass.blueprintName(for: container, sandbox: sandbox, pInfo: pInfo)

        #expect(blueprintName == nil)
    }

    @Test func outputFolderDefaultsToContainerName() async throws {
        let (container, _) = try await parseFirstContainerWithSandbox("""
            ===
            APIs #blueprint(api-springboot-monorepo)
            ===
            + HR

            === HR ===

            Employee
            ========
            ** employeeId : Id
            """)
        let pass = GenerateCodePass()

        let outputFolderSuffix = await pass.outputFolderSuffix(for: container)

        #expect(outputFolderSuffix == "APIs")
    }

    @Test func outputFolderTagOverridesContainerName() async throws {
        let (container, _) = try await parseFirstContainerWithSandbox("""
            ===
            APIs #blueprint(api-springboot-monorepo) #output-folder(base-services-hrservices)
            ===
            + HR

            === HR ===

            Employee
            ========
            ** employeeId : Id
            """)
        let pass = GenerateCodePass()

        let outputFolderSuffix = await pass.outputFolderSuffix(for: container)

        #expect(outputFolderSuffix == "base-services-hrservices")
    }

    @Test func blueprintTagWithEmptyParensIsParseError() async throws {
        let dsl = """
            ===
            APIs #blueprint()
            ===
            + HR

            === HR ===

            Employee
            ========
            ** employeeId : Id
            """
        let ctx = LoadContext(config: PipelineConfig())

        do {
            _ = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "GenerateCodePass_Tests")
            Issue.record("Expected empty #blueprint() to fail at parse time")
        } catch {
            #expect(error is ParsingError || error is Model_ParsingError)
        }
    }

    private func parseFirstContainerWithSandbox(_ dsl: String) async throws -> (C4Container, CodeGenerationSandbox) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "GenerateCodePass_Tests")
        await ctx.model.append(contentsOf: modelSpace)
        let container = try #require(await modelSpace.containers.first)
        let sandbox = await CodeGenerationSandbox(model: ctx.model, config: ctx.config)
        return (container, sandbox)
    }
}
