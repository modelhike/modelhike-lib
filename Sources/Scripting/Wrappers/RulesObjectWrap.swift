//
//  RulesObjectWrap.swift
//  ModelHike
//

import Foundation

public actor RulesObject_Wrap: ObjectWrapper {
    public let item: RulesObject
    public var attribs: Attributes { get async { await item.attribs } }

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = RulesObjectProperty(rawValue: propname) else {
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        return switch key {
        case .name: await item.name
        case .givenName: await item.givenname
        case .description: await item.description ?? ""
        case .hasDescription: (await item.description).map { $0.isNotEmpty } ?? false
        case .ruleType: await item.ruleSetKind.rawValue
        case .inputs: await item.inputs
        case .outputs: await item.outputs
        case .hitPolicy: await item.hitPolicy ?? ""
        case .source: await item.source ?? ""
        case .conditionalRules: await item.conditionalRules
        case .decisionTable: await item.decisionTable
        case .treeNodes: await item.treeNodes
        case .scoreRules: await item.scoreRules
        case .classifications: await item.classifications
        case .matchingRule: await item.matchingRule
        case .formulas: await item.formulas
        case .constraintRules: await item.constraintRules
        case .compositionCalls: await item.compositionCalls
        }
    }

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws -> Sendable {
        if await item.attribs.has(propname) {
            return await item.attribs[propname]
        }
        throw Suggestions.invalidPropertyInCall(propname, candidates: RulesObjectProperty.allCases.map(\.rawValue), pInfo: pInfo)
    }

    public var debugDescription: String { get async { await item.debugDescription } }

    public init(_ item: RulesObject) {
        self.item = item
    }
}

private enum RulesObjectProperty: String, CaseIterable {
    case name
    case givenName = "given-name"
    case description
    case hasDescription = "has-description"
    case ruleType = "rule-type"
    case inputs
    case outputs
    case hitPolicy = "hit-policy"
    case source
    case conditionalRules = "conditional-rules"
    case decisionTable = "decision-table"
    case treeNodes = "tree-nodes"
    case scoreRules = "score-rules"
    case classifications
    case matchingRule = "matching-rule"
    case formulas
    case constraintRules = "constraint-rules"
    case compositionCalls = "composition-calls"
}
