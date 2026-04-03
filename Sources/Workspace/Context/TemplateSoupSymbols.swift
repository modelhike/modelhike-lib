//
//  TemplateSoupSymbols.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public struct TemplateSoupSymbols: Sendable {
    public private(set) var modifiers: [String: Modifier] = [:]
    public private(set) var statements: [any FileTemplateStmtConfig] = []
    public private(set) var statementsByKeyword: [String: any FileTemplateStmtConfig] = [:]
    public private(set) var infixOperators: [InfixOperatorProtocol] = []
    private var infixOperatorsByName: [String: [InfixOperatorProtocol]] = [:]

    public mutating func add(modifiers modifiersList: [Modifier]) {
        for modifier in modifiersList {
            self.modifiers[modifier.name] = modifier
        }
    }
    
    public mutating func add(stmts stmtsList: [any FileTemplateStmtConfig]) {
        self.statements.append(contentsOf: stmtsList)
        for config in stmtsList {
            statementsByKeyword[config.keyword] = config
        }
    }
    
    public mutating func add(infixOperators operatorsList: [InfixOperatorProtocol]) {
        self.infixOperators.append(contentsOf: operatorsList)
        for op in operatorsList {
            infixOperatorsByName[op.name, default: []].append(op)
        }
    }

    public func infixOperators(named name: String) -> [InfixOperatorProtocol] {
        infixOperatorsByName[name] ?? []
    }

    public func hasInfixOperator(named name: String) -> Bool {
        infixOperatorsByName[name] != nil
    }

    public var allInfixOperatorNames: [String] {
        Array(infixOperatorsByName.keys)
    }
}
