//
//  RulesObject.swift
//  ModelHike
//

import Foundation

public enum RuleSetKind: String, Sendable {
    case conditional
    case decisionTable
    case decisionTree
    case scoring
    case matching
    case formula
    case constraint
    case composed
    case mixed
}

public struct RuleParam: Sendable {
    public let name: String
    public let typeName: String?
}

public struct ConditionalRule: Sendable {
    public let name: String
    public var whenClauses: [String]
    public var thenClauses: [String]
    public let pInfo: ParsedInfo
}

public struct DecisionTableRow: Sendable {
    public let cells: [String]
    public let pInfo: ParsedInfo
}

public struct DecisionTable: Sendable {
    public var inputColumns: [String]
    public var outputColumns: [String]
    public var rows: [DecisionTableRow]
}

public struct DecisionTreeNode: Sendable {
    public let conditionOrAction: String
    public let isCondition: Bool
    public let depth: Int
    public let pInfo: ParsedInfo
}

public struct ScoreRule: Sendable {
    public let name: String
    public var clauses: [DSLBodyLine]
    public let pInfo: ParsedInfo
}

public struct ClassificationRule: Sendable {
    public let outputName: String
    public var clauses: [DSLBodyLine]
    public let pInfo: ParsedInfo
}

public struct MatchingRule: Sendable {
    public var filterClauses: [DSLBodyLine]
    public var rankClauses: [DSLBodyLine]
    public var limit: String?
}

public struct FormulaRule: Sendable {
    public let name: String
    public let typeName: String?
    public var clauses: [DSLBodyLine]
    public let pInfo: ParsedInfo
}

public struct ConstraintRule: Sendable {
    public let name: String
    public var whenClauses: [String]
    public var rejectClauses: [String]
    public let pInfo: ParsedInfo
}

public struct RuleCompositionCall: Sendable {
    public let target: String
    public let arguments: String?
    public let result: String?
    public let pInfo: ParsedInfo
}

public actor RulesObject: ArtifactHolderWithAttachedSections, HasTechnicalImplications_Actor, HasDescription_Actor {
    let sourceLocation: SourceLocation

    public let attribs = Attributes()
    public let tags = Tags()
    public let technicalImplications = TechnicalImplications()
    public let annotations = Annotations()
    public var attachedSections = AttachedSections()
    public var attached: [Artifact] = []

    public let givenname: String
    public let name: String
    public let dataType: ArtifactKind = .rules
    public private(set) var description: String?

    public private(set) var directives: [DSLDirective] = []
    public private(set) var inputs: [RuleParam] = []
    public private(set) var outputs: [RuleParam] = []
    public private(set) var hitPolicy: String?
    public private(set) var source: String?
    public private(set) var scoreRange: String?
    public private(set) var ruleSetKind: RuleSetKind = .mixed

    public private(set) var conditionalRules: [ConditionalRule] = []
    public private(set) var decisionTable = DecisionTable(inputColumns: [], outputColumns: [], rows: [])
    public private(set) var treeNodes: [DecisionTreeNode] = []
    public private(set) var scoreRules: [ScoreRule] = []
    public private(set) var classifications: [ClassificationRule] = []
    public private(set) var matchingRule = MatchingRule(filterClauses: [], rankClauses: [], limit: nil)
    public private(set) var formulas: [FormulaRule] = []
    public private(set) var constraintRules: [ConstraintRule] = []
    public private(set) var compositionCalls: [RuleCompositionCall] = []
    public private(set) var assignments: [DSLBodyLine] = []

    public func setDescription(_ value: String?) {
        description = value
    }

    @discardableResult
    public func appendAttached(_ item: Artifact) -> Self {
        attached.append(item)
        return self
    }

    public func append(directive: DSLDirective) {
        directives.append(directive)
        switch directive.name.lowercased() {
        case "input": inputs.append(contentsOf: Self.parseParams(directive.value))
        case "output": outputs.append(contentsOf: Self.parseParams(directive.value))
        case "hit": hitPolicy = directive.value
        case "source": source = directive.value
        case "score": scoreRange = directive.value
        default: break
        }
    }

    public func append(rule: ConditionalRule) {
        conditionalRules.append(rule)
        updateKind(.conditional)
    }

    public func appendTableHeader(inputColumns: [String], outputColumns: [String]) {
        decisionTable.inputColumns = inputColumns
        decisionTable.outputColumns = outputColumns
        updateKind(.decisionTable)
    }

    public func append(tableRow: DecisionTableRow) {
        decisionTable.rows.append(tableRow)
        updateKind(.decisionTable)
    }

    public func append(treeNode: DecisionTreeNode) {
        treeNodes.append(treeNode)
        updateKind(.decisionTree)
    }

    public func append(score: ScoreRule) {
        scoreRules.append(score)
        updateKind(.scoring)
    }

    public func append(classification: ClassificationRule) {
        classifications.append(classification)
        updateKind(.scoring)
    }

    public func appendFilterClause(_ line: DSLBodyLine) {
        matchingRule.filterClauses.append(line)
        updateKind(.matching)
    }

    public func appendRankClause(_ line: DSLBodyLine) {
        matchingRule.rankClauses.append(line)
        updateKind(.matching)
    }

    public func setLimit(_ limit: String) {
        matchingRule.limit = limit
        updateKind(.matching)
    }

    public func append(formula: FormulaRule) {
        formulas.append(formula)
        updateKind(.formula)
    }

    public func append(constraint: ConstraintRule) {
        constraintRules.append(constraint)
        updateKind(.constraint)
    }

    public func append(compositionCall: RuleCompositionCall) {
        compositionCalls.append(compositionCall)
        updateKind(.composed)
    }

    public func append(assignment: DSLBodyLine) {
        assignments.append(assignment)
    }

    public func appendLineToLastConditional(_ line: DSLBodyLine) {
        guard conditionalRules.isNotEmpty else { return }
        if line.text.hasPrefix("when:") {
            conditionalRules[conditionalRules.count - 1].whenClauses.append(line.text.remainingLine(after: "when:"))
        } else if line.text.hasPrefix("then:") {
            conditionalRules[conditionalRules.count - 1].thenClauses.append(line.text.remainingLine(after: "then:"))
        } else {
            conditionalRules[conditionalRules.count - 1].thenClauses.append(line.text)
        }
    }

    public func appendLineToLastScore(_ line: DSLBodyLine) {
        guard scoreRules.isNotEmpty else { return }
        scoreRules[scoreRules.count - 1].clauses.append(line)
    }

    public func appendLineToLastClassification(_ line: DSLBodyLine) {
        guard classifications.isNotEmpty else { return }
        classifications[classifications.count - 1].clauses.append(line)
    }

    public func appendLineToLastFormula(_ line: DSLBodyLine) {
        guard formulas.isNotEmpty else { return }
        formulas[formulas.count - 1].clauses.append(line)
    }

    public func appendLineToLastConstraint(_ line: DSLBodyLine) {
        guard constraintRules.isNotEmpty else { return }
        if line.text.hasPrefix("when:") {
            constraintRules[constraintRules.count - 1].whenClauses.append(line.text.remainingLine(after: "when:"))
        } else if line.text.hasPrefix("reject:") {
            constraintRules[constraintRules.count - 1].rejectClauses.append(line.text.remainingLine(after: "reject:"))
        }
    }

    private func updateKind(_ newKind: RuleSetKind) {
        if ruleSetKind == .mixed {
            ruleSetKind = newKind
        } else if ruleSetKind != newKind {
            ruleSetKind = .mixed
        }
    }

    private static func parseParams(_ value: String) -> [RuleParam] {
        ExtendedDSLParserSupport.splitCommaList(value).map { part in
            let pieces = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            if pieces.count == 2 {
                return RuleParam(name: String(pieces[0]).trim(), typeName: String(pieces[1]).trim())
            }
            return RuleParam(name: part.trim(), typeName: nil)
        }
    }

    public var debugDescription: String {
        get async {
            "\(name) : rules kind=\(ruleSetKind.rawValue)"
        }
    }

    public init(name: String, sourceLocation: SourceLocation) {
        self.sourceLocation = sourceLocation
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
    }
}
