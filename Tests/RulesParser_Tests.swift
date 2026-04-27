import Testing
@testable import ModelHike

@Suite struct RulesParser_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "RulesParser_Tests")
        await ctx.model.append(contentsOf: modelSpace)
        try await ctx.model.resolveAndLinkItems(with: ctx)
        return (ctx, modelSpace)
    }

    private func moduleNamed(_ name: String, space: ModelSpace) async -> C4Component? {
        for module in await space.modules.snapshot() {
            if await module.name == name { return module }
        }
        return nil
    }

    private func rulesNamed(_ name: String, in module: C4Component) async throws -> RulesObject {
        for item in await module.items {
            if let rules = item as? RulesObject, await rules.name == name {
                return rules
            }
        }
        return try #require(nil as RulesObject?)
    }

    @Test func decisionTableRulesParseParamsHitPolicyHeaderAndRows() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Pricing

            === Pricing ===

            Shipping Rules
            ??????
            @ input:: weight: Float, destination: String
            @ output:: rate: Float, carrier: String
            @ hit:: first
            || weight | destination || rate | carrier ||
            || ------ | ----------- || ---- | ------- ||
            || > 10 | EU || 20 | DHL ||
            """)

        let module = try #require(await moduleNamed("Pricing", space: space))
        let rules = try await rulesNamed("ShippingRules", in: module)

        #expect(await rules.ruleSetKind == .decisionTable)
        #expect(await rules.inputs.map(\.name) == ["weight", "destination"])
        #expect(await rules.outputs.map(\.name) == ["rate", "carrier"])
        #expect(await rules.hitPolicy == "first")

        let table = await rules.decisionTable
        #expect(table.inputColumns == ["weight", "destination"])
        #expect(table.outputColumns == ["rate", "carrier"])
        #expect(table.rows.count == 1)
        let row = try #require(table.rows.first)
        #expect(row.cells == ["> 10", "EU", "20", "DHL"])
    }

    @Test func mixedRulesParseConditionalScoringMatchingFormulaConstraintAndComposition() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Pricing

            === Pricing ===

            Pricing Rules
            ??????
            @ input:: customer: Customer
            @ output:: discount: Float
            @ source:: Agent where status == "ONLINE"
            @ score:: range 0..100
            rule VIP
            | when: customer.tier == "VIP"
            | then: discount = 0.2
            score loyalty
            | +10 when purchases > 5
            classify riskLevel
            | high when score > 80
            filter
            | status == "ONLINE"
            rank
            | distance asc
            limit: 5
            = premium: Float
            | base * 1.2
            constraint total
            | when: total < 0
            | reject: negative total
            decide @"OtherRules" with customer -> result
            """)

        let module = try #require(await moduleNamed("Pricing", space: space))
        let rules = try await rulesNamed("PricingRules", in: module)

        #expect(await rules.ruleSetKind == .mixed)
        #expect(await rules.source == "Agent where status == \"ONLINE\"")
        #expect(await rules.scoreRange == "range 0..100")
        #expect(await rules.conditionalRules.first?.whenClauses == ["customer.tier == \"VIP\""])
        #expect(await rules.conditionalRules.first?.thenClauses == ["discount = 0.2"])
        #expect(await rules.scoreRules.first?.clauses.first?.text == "+10 when purchases > 5")
        #expect(await rules.classifications.first?.outputName == "riskLevel")
        #expect(await rules.matchingRule.filterClauses.first?.text == "status == \"ONLINE\"")
        #expect(await rules.matchingRule.rankClauses.first?.text == "distance asc")
        #expect(await rules.matchingRule.limit == "5")
        #expect(await rules.formulas.first?.name == "premium")
        #expect(await rules.formulas.first?.typeName == "Float")
        #expect(await rules.constraintRules.first?.rejectClauses == ["negative total"])
        #expect(await rules.compositionCalls.first?.target == "OtherRules")
        #expect(await rules.compositionCalls.first?.result == "result")
    }

    @Test func decisionTreeRulesParseTreeNodes() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Risk

            === Risk ===

            Risk Tree
            ??????
            @ input:: applicant: Applicant
            @ output:: decision: String
            ├── [income > 100000]
            └── approve
            """)

        let module = try #require(await moduleNamed("Risk", space: space))
        let rules = try await rulesNamed("RiskTree", in: module)

        #expect(await rules.ruleSetKind == .decisionTree)
        #expect(await rules.treeNodes.count == 2)
        #expect(await rules.treeNodes.first?.isCondition == true)
        #expect(await rules.treeNodes.last?.conditionOrAction == "approve")
    }

    @Test func matchingOnlyRulesUseMatchingKind() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support ===

            Agent Match
            ??????
            @ input:: ticket: Ticket
            @ output:: assignee: Agent
            @ source:: Agent where online == true
            filter
            | skill == ticket.skill
            rank
            | load asc
            limit: 1
            """)

        let module = try #require(await moduleNamed("Support", space: space))
        let rules = try await rulesNamed("AgentMatch", in: module)

        #expect(await rules.ruleSetKind == .matching)
        #expect(await rules.matchingRule.filterClauses.first?.text == "skill == ticket.skill")
        #expect(await rules.matchingRule.rankClauses.first?.text == "load asc")
        #expect(await rules.matchingRule.limit == "1")
    }

    @Test func constraintOnlyRulesUseConstraintKind() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Risk

            === Risk ===

            Validation Rules
            ??????
            @ input:: order: Order
            @ output:: valid: Bool
            constraint positive
            | when: order.total < 0
            | reject: total must be positive
            constraint maxQty
            | when: order.qty > 1000
            | reject: quantity exceeds limit
            """)

        let module = try #require(await moduleNamed("Risk", space: space))
        let rules = try await rulesNamed("ValidationRules", in: module)

        #expect(await rules.ruleSetKind == .constraint)
        #expect(await rules.constraintRules.count == 2)
        #expect(await rules.constraintRules[0].name == "positive")
        #expect(await rules.constraintRules[0].whenClauses == ["order.total < 0"])
        #expect(await rules.constraintRules[0].rejectClauses == ["total must be positive"])
        #expect(await rules.constraintRules[1].name == "maxQty")
    }

    @Test func scoringOnlyRulesUseScoringKind() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Risk

            === Risk ===

            Credit Score
            ??????
            @ input:: applicant: Applicant
            @ output:: score: Int
            @ score:: range 0..850
            score income
            | +100 when income > 50000
            | +200 when income > 100000
            score history
            | +50 when years > 5
            classify tier
            | gold when score > 700
            | silver when score > 500
            """)

        let module = try #require(await moduleNamed("Risk", space: space))
        let rules = try await rulesNamed("CreditScore", in: module)

        #expect(await rules.ruleSetKind == .scoring)
        #expect(await rules.scoreRules.count == 2)
        #expect(await rules.scoreRules[0].clauses.count == 2)
        #expect(await rules.scoreRules[1].name == "history")
        #expect(await rules.classifications.count == 1)
        #expect(await rules.classifications[0].clauses.count == 2)
    }

    @Test func multipleConditionalRulesParseCorrectly() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Pricing

            === Pricing ===

            Discount Rules
            ??????
            @ input:: customer: Customer
            @ output:: discount: Float
            rule VIP
            | when: customer.tier == "VIP"
            | then: discount = 0.3
            rule Employee
            | when: customer.isEmployee == true
            | then: discount = 0.5
            rule Seasonal
            | when: customer.season == "holiday"
            | then: discount = 0.1
            """)

        let module = try #require(await moduleNamed("Pricing", space: space))
        let rules = try await rulesNamed("DiscountRules", in: module)

        #expect(await rules.ruleSetKind == .conditional)
        #expect(await rules.conditionalRules.count == 3)
        #expect(await rules.conditionalRules[2].name == "Seasonal")
        #expect(await rules.conditionalRules[2].thenClauses == ["discount = 0.1"])
    }

    @Test func formulaOnlyRulesUseFormulaKindAndStopBeforeNextObject() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Svc
            ===
            + Pricing

            === Pricing ===

            Premium Formula
            ??????
            @ input:: base: Float
            @ output:: premium: Float
            = premium: Float
            | base * 1.2

            Customer
            ========
            ** id: Id
            """)

        let module = try #require(await moduleNamed("Pricing", space: space))
        let rules = try await rulesNamed("PremiumFormula", in: module)

        #expect(await rules.ruleSetKind == .formula)
        #expect(await rules.formulas.first?.clauses.first?.text == "base * 1.2")
        let customer = try #require(await ctx.model.types.get(for: "Customer") as? DomainObject)
        #expect(await customer.name == "Customer")
    }

    @Test func emptyRulesBlockStillCreatesObject() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Pricing

            === Pricing ===

            Placeholder Rules
            ??????
            @ input:: order: Order
            @ output:: result: Bool
            """)

        let module = try #require(await moduleNamed("Pricing", space: space))
        let rules = try await rulesNamed("PlaceholderRules", in: module)

        #expect(await rules.ruleSetKind == .mixed)
        #expect(await rules.conditionalRules.isEmpty)
        #expect(await rules.inputs.count == 1)
        #expect(await rules.outputs.count == 1)
    }

    @Test func rulesWithDecisionTreeNodes() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Pricing

            === Pricing ===

            Tier Rules
            ??????
            @ input:: customer: Customer
            @ output:: tier: String
            +-- [revenue > 1M] -> gold
            +-- [revenue > 100K] -> silver
            \-- else -> bronze
            """#)

        let module = try #require(await moduleNamed("Pricing", space: space))
        let rules = try await rulesNamed("TierRules", in: module)

        #expect(await rules.ruleSetKind == .decisionTree)
        #expect(await rules.treeNodes.count == 3)
    }

    @Test func rulesWithMatchingRuleAndCompositionCall() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Pricing

            === Pricing ===

            Routing Rules
            ??????
            @ input:: request: Request
            @ output:: handler: String
            filter
            | when: request.active == true
            rank
            | by: request.priority desc
            decide @"Validation Rules"
            """)

        let module = try #require(await moduleNamed("Pricing", space: space))
        let rules = try await rulesNamed("RoutingRules", in: module)

        #expect(await rules.matchingRule.filterClauses.count == 1)
        #expect(await rules.matchingRule.rankClauses.count == 1)
        #expect(await rules.compositionCalls.count == 1)
        #expect(await rules.compositionCalls.first?.target == "Validation Rules")
    }

    @Test func twoRulesBlocksInSameModuleAreIndependent() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Pricing

            === Pricing ===

            Discount Rules
            ??????
            @ input:: order: Order
            @ output:: discount: Float
            rule VIP
            | when: tier == "VIP"
            | then: discount = 0.3

            Tax Rules
            ??????
            @ input:: order: Order
            @ output:: tax: Float
            = tax: Float
            | order.total * 0.1
            """)

        let module = try #require(await moduleNamed("Pricing", space: space))
        let all = await module.rulesObjects
        #expect(all.count == 2)

        let discount = try await rulesNamed("DiscountRules", in: module)
        #expect(await discount.ruleSetKind == .conditional)

        let tax = try await rulesNamed("TaxRules", in: module)
        #expect(await tax.ruleSetKind == .formula)
    }
}
