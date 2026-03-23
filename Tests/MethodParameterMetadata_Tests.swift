import Testing
@testable import ModelHike

@Suite struct MethodParameterMetadata_Tests {

    // MARK: - >>> metadata line parsing

    @Test func requiredParamGetsRequiredKind() async throws {
        let method = try await parseMethod("""
            >>> * customerId: Int
            ~ createOrder(customerId: Int)
            """)

        let params = await method.parameters
        #expect(params.count == 1)
        #expect(params[0].metadata.required == .yes)
        #expect(params[0].metadata.isOutput == false)
    }

    @Test func optionalParamGetsOptionalKind() async throws {
        let method = try await parseMethod("""
            >>> - notes: String
            ~ createOrder(notes: String)
            """)

        let params = await method.parameters
        #expect(params[0].metadata.required == .no)
    }

    @Test func outputTagSetsIsOutput() async throws {
        let method = try await parseMethod("""
            >>> * orderId: Int #output
            ~ createOrder(orderId: Int)
            """)

        let params = await method.parameters
        #expect(params[0].metadata.isOutput == true)
        #expect(params[0].metadata.tags.contains(where: { $0.name == "output" }))
    }

    @Test func defaultValueIsCaptured() async throws {
        let method = try await parseMethod("""
            >>> - notes: String = nil
            ~ createOrder(notes: String)
            """)

        let params = await method.parameters
        #expect(params[0].metadata.defaultValue == "nil")
    }

    @Test func constraintIsCaptured() async throws {
        let method = try await parseMethod("""
            >>> - notes: String { length = 500 }
            ~ createOrder(notes: String)
            """)

        let params = await method.parameters
        let constraints = params[0].metadata.constraints
        #expect(constraints.count == 1)
        #expect(constraints[0].name == "length")
        #expect(ConstraintRenderer.renderValue(of: constraints[0]) == "500")
    }

    @Test func attributesAreCaptured() async throws {
        // Use identifier attribute values — bare numbers aren't matched by variableValue
        let method = try await parseMethod("""
            >>> - status: String (source=legacy, format=compact)
            ~ createOrder(status: String)
            """)

        let params = await method.parameters
        let attribs = params[0].metadata.attribs
        #expect(attribs.contains(where: { $0.key == "source" && ($0.value as? String) == "legacy" }))
        #expect(attribs.contains(where: { $0.key == "format" && ($0.value as? String) == "compact" }))
    }

    @Test func validValueSetIsParsedAsArray() async throws {
        let method = try await parseMethod("""
            >>> - status: String <"NEW", "ACTIVE", "DONE">
            ~ updateStatus(status: String)
            """)

        let params = await method.parameters
        #expect(params[0].metadata.validValueSet == ["\"NEW\"", "\"ACTIVE\"", "\"DONE\""])
    }

    @Test func requiredOutputParamCombinesMetadata() async throws {
        let method = try await parseMethod("""
            >>> * amount: Decimal = 0 { min = 0 } #output
            ~ transferFunds(amount: Decimal)
            """)

        let params = await method.parameters
        #expect(params.count == 1)
        let amount = params[0]
        #expect(amount.name == "amount")
        #expect(amount.metadata.required == .yes)
        #expect(amount.metadata.defaultValue == "0")
        #expect(amount.metadata.isOutput == true)
        #expect(amount.metadata.constraints.count == 1)
        #expect(ConstraintRenderer.renderValue(of: amount.metadata.constraints[0]) == "0")
    }

    @Test func paramWithNoMetadataLineGetsDefaults() async throws {
        let method = try await parseMethod("""
            ~ createOrder(customerId: Id)
            """)

        let params = await method.parameters
        #expect(params.count == 1)
        #expect(params[0].name == "customerId")
        // No >>> line — all defaults
        #expect(params[0].metadata.required == .no)
        #expect(params[0].metadata.defaultValue == nil)
        #expect(params[0].metadata.constraints.isEmpty)
        #expect(params[0].metadata.attribs.isEmpty)
        #expect(params[0].metadata.tags.isEmpty)
    }

    @Test func noMetadataLinesLeavesParamsWithDefaults() async throws {
        let method = try await parseMethod("~ doSomething(amount: Decimal)")

        let params = await method.parameters
        #expect(params.count == 1)
        #expect(params[0].metadata.required == .no)
        #expect(params[0].metadata.constraints.isEmpty)
        #expect(params[0].metadata.attribs.isEmpty)
        #expect(params[0].metadata.tags.isEmpty)
    }

    @Test func multipleParamsEachGetOwnMetadata() async throws {
        let method = try await parseMethod("""
            >>> * orderId: Int
            >>> - notes: String = nil
            ~ createOrder(orderId: Int, notes: String)
            """)

        let params = await method.parameters
        #expect(params.count == 2)
        #expect(params[0].name == "orderId")
        #expect(params[0].metadata.required == .yes)
        #expect(params[1].name == "notes")
        #expect(params[1].metadata.required == .no)
        #expect(params[1].metadata.defaultValue == "nil")
    }

    @Test func setextMethodPreservesMetadata() async throws {
        let dsl = """
            ===
            TestService
            ===
            + TestModule

            === TestModule ===

            TestEntity
            ==========
            * id : Id

            >>> * percent: Float = 0 { min = 0 }
            applyDiscount(percent: Float) : TestEntity
            -------------------------------------------
            return self
            ---
            """
        let method = try await parseMethodFromClass(dsl, className: "TestEntity", methodName: "applyDiscount")

        let params = await method.parameters
        #expect(params.count == 1)
        #expect(params[0].name == "percent")
        #expect(params[0].metadata.defaultValue == "0")
        #expect(params[0].metadata.constraints.count == 1)
    }

    // MARK: - Helpers

    /// Wraps `methodDSL` inside a minimal container + module + class and returns the first method.
    private func parseMethod(_ methodDSL: String) async throws -> MethodObject {
        let dsl = """
            ===
            TestService
            ===
            + TestModule

            === TestModule ===

            TestEntity
            ==========
            \(methodDSL)
            """
        return try await parseMethodFromClass(dsl, className: "TestEntity", methodName: nil)
    }

    /// Parses `dsl` as a full model file and returns the named method from `className`.
    /// Pass `nil` for `methodName` to return the first method found.
    private func parseMethodFromClass(_ dsl: String, className: String, methodName: String?) async throws -> MethodObject {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "MethodParameterMetadata_Tests")
        await ctx.model.append(contentsOf: modelSpace)
        try await ctx.model.resolveAndLinkItems(with: ctx)

        let domainObject = try #require(await ctx.model.types.get(for: className))
        let methods = await domainObject.methods

        let method: MethodObject?
        if let methodName {
            var found: MethodObject? = nil
            for m in methods where await m.name == methodName {
                found = m
                break
            }
            method = found
        } else {
            method = methods.first
        }

        guard let method else {
            throw MethodParserTestError.methodNotFound(methodName ?? "<first>")
        }
        return method
    }
}

private enum MethodParserTestError: Error {
    case parseFailed
    case methodNotFound(String)
}
