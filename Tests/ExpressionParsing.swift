import Testing
@testable import ModelHike

@Suite struct ExpressionParsing_Tests {
    let context: LoadContext
    let pInfo: ParsedInfo
    let evaluator = RegularExpressionEvaluator()

    init() async throws {
        let obj1 = await DynamicTestObj(name: "n1", age: 1)
        let obj2 = await DynamicTestObj(name: "n2", age: 2)
        let obj3 = await DynamicTestObj(name: "", age: 3)
        let arr: [DynamicTestObj] = [obj1, obj2, obj3]

        let ctx = LoadContext(config: PipelineConfig())
        await ctx.symbols.addTemplate(infixOperators: DefaultOperatorsLibrary.infixOperators)
        await ctx.replace(variables: ["list": arr, "var1": true, "var2": false])
        self.context = ctx
        self.pInfo = await ParsedInfo.dummy(line: "", identifier: "test", loadCtx: ctx)
    }

    @Test func complexExpression1() async throws {
        let expn = "(var1 or var2 and var1 and var1 and var1) or (var2) and (var2 and var1)"
        let result = try await evaluator.evaluate(expression: expn, pInfo: pInfo) as! Bool
        #expect(result == false)
    }

    @Test func complexExpression2() async throws {
        let expn = "(var1 and var2 and var1 and var1 and var1) or (var2) and (var2 and var1)"
        let result = try await evaluator.evaluate(expression: expn, pInfo: pInfo) as! Bool
        #expect(result == false)
    }

    @Test func complexExpression3() async throws {
        let expn = "var1 and (var2 or var2) and var2 or var1"
        let result = try await evaluator.evaluate(expression: expn, pInfo: pInfo) as! Bool
        #expect(result == false)
    }

    @Test func complexExpression4() async throws {
        let expn = "var1 and (var2 or var1 and var1) and (var1 and var1) or var2"
        let result = try await evaluator.evaluate(expression: expn, pInfo: pInfo) as! Bool
        #expect(result == true)
    }

    @Test func invalidExpressionError() async throws {
        let expn = "(var1 and var2) hu var2"
        await #expect(throws: TemplateSoup_ParsingError.self) {
            try await evaluator.evaluate(expression: expn, pInfo: pInfo)
        }
    }

    @Test func stringEqualityOperator() async throws {
        await context.replace(variables: ["kind": "if", "other": "else"])
        let ok = try await evaluator.evaluate(expression: "kind == \"if\"", pInfo: pInfo) as! Bool
        #expect(ok == true)
        let no = try await evaluator.evaluate(expression: "kind == \"else\"", pInfo: pInfo) as! Bool
        #expect(no == false)
    }

    @Test func stringInStringArrayLiteral() async throws {
        await context.replace(variables: ["kind": "elseif", "missing": "xyz"])
        let ok = try await evaluator.evaluate(expression: "kind in [\"if\", \"elseif\", \"else\"]", pInfo: pInfo) as! Bool
        #expect(ok == true)
        let no = try await evaluator.evaluate(expression: "missing in [\"if\", \"else\"]", pInfo: pInfo) as! Bool
        #expect(no == false)
    }

    @Test func quotedStringWithSpaces() async throws {
        await context.replace(variables: ["name": "hello world"])
        let ok = try await evaluator.evaluate(expression: "name == \"hello world\"", pInfo: pInfo) as! Bool
        #expect(ok == true)
    }

    @Test func bracketArrayInParenGroup() async throws {
        await context.replace(variables: ["kind": "if", "var1": true])
        let ok = try await evaluator.evaluate(expression: "(kind in [\"if\", \"else\"]) and var1", pInfo: pInfo) as! Bool
        #expect(ok == true)
    }

    @Test func tokenizeDirectly() {
        let t1 = RegularExpressionEvaluator.tokenize(#"kind in ["if", "elseif"]"#)
        #expect(t1 == [
            .value("kind"),
            .value("in"),
            .value(#"["if", "elseif"]"#),
        ])

        let t2 = RegularExpressionEvaluator.tokenize("(var1 or var2)")
        #expect(t2 == [
            .openParen,
            .value("var1"),
            .value("or"),
            .value("var2"),
            .closeParen,
        ])

        let t3 = RegularExpressionEvaluator.tokenize(#"name == "hello world""#)
        #expect(t3 == [
            .value("name"),
            .value("=="),
            .value(#""hello world""#),
        ])
    }

    @Test func stringNotEqualsOperator() async throws {
        await context.replace(variables: ["kind": "if"])
        let ok = try await evaluator.evaluate(expression: "kind != \"else\"", pInfo: pInfo) as! Bool
        #expect(ok == true)
        let no = try await evaluator.evaluate(expression: "kind != \"if\"", pInfo: pInfo) as! Bool
        #expect(no == false)
    }

    @Test func intComparison() async throws {
        await context.replace(variables: ["port": 3001])
        let gt = try await evaluator.evaluate(expression: "port > 3000", pInfo: pInfo) as! Bool
        #expect(gt == true)
        let lt = try await evaluator.evaluate(expression: "port < 4000", pInfo: pInfo) as! Bool
        #expect(lt == true)
        let gte = try await evaluator.evaluate(expression: "port >= 3001", pInfo: pInfo) as! Bool
        #expect(gte == true)
        let lte = try await evaluator.evaluate(expression: "port <= 3001", pInfo: pInfo) as! Bool
        #expect(lte == true)
        let eq = try await evaluator.evaluate(expression: "port == 3001", pInfo: pInfo) as! Bool
        #expect(eq == true)
        let neq = try await evaluator.evaluate(expression: "port != 9999", pInfo: pInfo) as! Bool
        #expect(neq == true)
    }

    @Test func doubleComparison() async throws {
        await context.replace(variables: ["score": 3.14])
        let gt = try await evaluator.evaluate(expression: "score > 3.0", pInfo: pInfo) as! Bool
        #expect(gt == true)
        let lt = try await evaluator.evaluate(expression: "score < 4.0", pInfo: pInfo) as! Bool
        #expect(lt == true)
        let eq = try await evaluator.evaluate(expression: "score == 3.14", pInfo: pInfo) as! Bool
        #expect(eq == true)
    }

    @Test func intArithmetic() async throws {
        await context.replace(variables: ["count": 5])
        let sum = try await evaluator.evaluate(expression: "count + 3", pInfo: pInfo) as! Int
        #expect(sum == 8)
        let diff = try await evaluator.evaluate(expression: "count - 2", pInfo: pInfo) as! Int
        #expect(diff == 3)
        let prod = try await evaluator.evaluate(expression: "count * 4", pInfo: pInfo) as! Int
        #expect(prod == 20)
        let quot = try await evaluator.evaluate(expression: "count / 2", pInfo: pInfo) as! Int
        #expect(quot == 2)
    }

    @Test func doubleArithmetic() async throws {
        await context.replace(variables: ["value": 5.0])
        let sum = try await evaluator.evaluate(expression: "value + 3.0", pInfo: pInfo) as! Double
        #expect(sum == 8.0)
        let quot = try await evaluator.evaluate(expression: "value / 2.0", pInfo: pInfo) as! Double
        #expect(quot == 2.5)
    }

    @Test func typeMismatchThrows() async throws {
        await context.replace(variables: ["port": 3001])
        await #expect(throws: TemplateSoup_ParsingError.self) {
            try await evaluator.evaluate(expression: "port > 3.0", pInfo: pInfo)
        }
    }

    actor DynamicTestObj: DynamicMemberLookup, HasAttributes {
        let attribs = Attributes()

        func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
            return await attribs[propname]
        }

        init(name: String, age: Int) async {
            await attribs.set("name", value: name)
            await attribs.set("age", value: age)
        }
    }
}
