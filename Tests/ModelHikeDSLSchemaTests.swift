import Foundation
import ModelHike
import Testing

@Suite("ModelHikeDSLSchema")
struct ModelHikeDSLSchemaTests {

    @Test func bundledLoadsAllThreeFiles() throws {
        let schema = try #require(ModelHikeDSLSchema.bundled)
        #expect(!schema.modelHikeDSL.isEmpty)
        #expect(!schema.codeLogicDSL.isEmpty)
        #expect(!schema.templateSoupDSL.isEmpty)
    }

    @Test func modelHikeDSLContainsExpectedContent() throws {
        let schema = try #require(ModelHikeDSLSchema.bundled)
        #expect(schema.modelHikeDSL.contains("ModelHike DSL"))
        #expect(schema.modelHikeDSL.contains(".modelhike"))
    }

    @Test func codeLogicDSLContainsExpectedContent() throws {
        let schema = try #require(ModelHikeDSLSchema.bundled)
        #expect(schema.codeLogicDSL.contains("Code Logic"))
        #expect(schema.codeLogicDSL.contains("MethodObject"))
    }

    @Test func templateSoupDSLContainsExpectedContent() throws {
        let schema = try #require(ModelHikeDSLSchema.bundled)
        #expect(schema.templateSoupDSL.contains("TemplateSoup"))
        #expect(schema.templateSoupDSL.contains("SoupyScript"))
    }
}
