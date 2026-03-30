//
//  Operator.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public struct InfixOperator<A, B, T: Sendable> : InfixOperatorProtocol {
    public var name : String
    public var lhsType: any Any.Type { _lhsType }
    public var rhsType: any Any.Type { _rhsType }
    private let _lhsType: A.Type
    private let _rhsType: B.Type
    private let handler: @Sendable (A, B) -> T
    public var kind : OperatorKind { .infix }

    public func applyTo(lhs : Sendable?, rhs: Sendable?, pInfo: ParsedInfo) throws -> Sendable {
        guard let typedLhs = lhs as? A, type(of: typedLhs) == _lhsType else {
            throw TemplateSoup_ParsingError.infixOperatorCalledOnwrongLhsType(self.name, runtimeTypeName(of: lhs), pInfo)
        }
        guard let typedRhs = rhs as? B, type(of: typedRhs) == _rhsType else {
            throw TemplateSoup_ParsingError.infixOperatorCalledOnwrongRhsType(self.name, runtimeTypeName(of: rhs), pInfo)
        }
        return handler(typedLhs, typedRhs)
    }
    
    public init(name: String, handler: @escaping @Sendable(A, B) -> T) {
        self.name = name
        self._lhsType = A.self
        self._rhsType = B.self
        self.handler = handler
    }
}

public struct SuffixOperator<A, T> : Operator {
    public var name : String
    public var callerType: A.Type
    private var handler: @Sendable(A) -> T
    
    public var kind : OperatorKind { .infix }

    public init(name: String, handler: @escaping @Sendable(A) -> T) {
        self.name = name
        self.callerType = A.self
        self.handler = handler
    }
}

public struct PrefixOperator<A, T> : Operator {
    public var name : String
    public var callerType: A.Type
    private var handler: @Sendable(A) -> T
    
    public var kind : OperatorKind { .infix }

    public init(name: String, handler: @escaping @Sendable(A) -> T) {
        self.name = name
        self.callerType = A.self
        self.handler = handler
    }
}

public protocol InfixOperatorProtocol : Operator {
    var lhsType: any Any.Type { get }
    var rhsType: any Any.Type { get }
    func applyTo(lhs : Sendable?, rhs: Sendable?, pInfo: ParsedInfo) throws -> Sendable
}

public protocol Operator: Sendable {
    var name : String {get set}
    var kind : OperatorKind {get}
}

public enum OperatorKind {
    case infix, suffix, prefix
}
