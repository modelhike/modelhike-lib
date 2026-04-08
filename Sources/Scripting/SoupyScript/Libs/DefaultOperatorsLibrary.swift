//
//  DefaultOperatorsLibrary.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public struct DefaultOperatorsLibrary {

    public static var infixOperators: [InfixOperatorProtocol] {
        return [
            // String tests
            startsWithOperator,
            endsWithOperator,
            containsOperator,
            matchesOperator,

            // Equality
            stringEqualsOperator,
            stringNotEqualsOperator,
            doubleEqualsOperator,
            doubleNotEqualsOperator,
            intEqualsOperator,
            intNotEqualsOperator,

            // Numeric comparison (Double)
            doubleLessThanOperator,
            doubleGreaterThanOperator,
            doubleLessThanOrEqualOperator,
            doubleGreaterThanOrEqualOperator,

            // Numeric comparison (Int)
            intLessThanOperator,
            intGreaterThanOperator,
            intLessThanOrEqualOperator,
            intGreaterThanOrEqualOperator,

            // Arithmetic (Double)
            doubleAddOperator,
            doubleSubtractOperator,
            doubleMultiplyOperator,
            doubleDivideOperator,

            // Arithmetic (Int)
            intAddOperator,
            intSubtractOperator,
            intMultiplyOperator,
            intDivideOperator,

            // Membership
            inDoubleArrayOperator,
            notInDoubleArrayOperator,
            inIntArrayOperator,
            notInIntArrayOperator,
            inStringArrayOperator,
            notInStringArrayOperator,

            // Logical
            orOperator,
            andOperator,
        ]
    }

    // MARK: - String tests

    public static var startsWithOperator: InfixOperatorProtocol {
        CreateOperator.infix("starts-with") { (lhs: String, rhs: String) in lhs.hasPrefix(rhs) }
    }

    public static var endsWithOperator: InfixOperatorProtocol {
        CreateOperator.infix("ends-with") { (lhs: String, rhs: String) in lhs.hasSuffix(rhs) }
    }

    public static var containsOperator: InfixOperatorProtocol {
        CreateOperator.infix("contains") { (lhs: String, rhs: String) in lhs.contains(rhs) }
    }

    public static var matchesOperator: InfixOperatorProtocol {
        CreateOperator.infix("matches") { (lhs: String, rhs: String) in
            if let regex = try? NSRegularExpression(pattern: rhs) {
                return regex.numberOfMatches(in: lhs, range: NSRange(lhs.startIndex..., in: lhs))
                    > 0
            }
            return false
        }
    }

    // MARK: - Equality (String)

    public static var stringEqualsOperator: InfixOperatorProtocol {
        CreateOperator.infix("==") { (lhs: String, rhs: String) in lhs == rhs }
    }

    public static var stringNotEqualsOperator: InfixOperatorProtocol {
        CreateOperator.infix("!=") { (lhs: String, rhs: String) in lhs != rhs }
    }

    // MARK: - Equality (Double)

    public static var doubleEqualsOperator: InfixOperatorProtocol {
        CreateOperator.infix("==") { (lhs: Double, rhs: Double) in lhs == rhs }
    }

    public static var doubleNotEqualsOperator: InfixOperatorProtocol {
        CreateOperator.infix("!=") { (lhs: Double, rhs: Double) in lhs != rhs }
    }

    // MARK: - Equality (Int)

    public static var intEqualsOperator: InfixOperatorProtocol {
        CreateOperator.infix("==") { (lhs: Int, rhs: Int) in lhs == rhs }
    }

    public static var intNotEqualsOperator: InfixOperatorProtocol {
        CreateOperator.infix("!=") { (lhs: Int, rhs: Int) in lhs != rhs }
    }

    // MARK: - Comparison (Double)

    public static var doubleLessThanOperator: InfixOperatorProtocol {
        CreateOperator.infix("<") { (lhs: Double, rhs: Double) in lhs < rhs }
    }

    public static var doubleGreaterThanOperator: InfixOperatorProtocol {
        CreateOperator.infix(">") { (lhs: Double, rhs: Double) in lhs > rhs }
    }

    public static var doubleLessThanOrEqualOperator: InfixOperatorProtocol {
        CreateOperator.infix("<=") { (lhs: Double, rhs: Double) in lhs <= rhs }
    }

    public static var doubleGreaterThanOrEqualOperator: InfixOperatorProtocol {
        CreateOperator.infix(">=") { (lhs: Double, rhs: Double) in lhs >= rhs }
    }

    // MARK: - Comparison (Int)

    public static var intLessThanOperator: InfixOperatorProtocol {
        CreateOperator.infix("<") { (lhs: Int, rhs: Int) in lhs < rhs }
    }

    public static var intGreaterThanOperator: InfixOperatorProtocol {
        CreateOperator.infix(">") { (lhs: Int, rhs: Int) in lhs > rhs }
    }

    public static var intLessThanOrEqualOperator: InfixOperatorProtocol {
        CreateOperator.infix("<=") { (lhs: Int, rhs: Int) in lhs <= rhs }
    }

    public static var intGreaterThanOrEqualOperator: InfixOperatorProtocol {
        CreateOperator.infix(">=") { (lhs: Int, rhs: Int) in lhs >= rhs }
    }

    // MARK: - Arithmetic (Double)

    public static var doubleAddOperator: InfixOperatorProtocol {
        CreateOperator.infix("+") { (lhs: Double, rhs: Double) in lhs + rhs }
    }

    public static var doubleSubtractOperator: InfixOperatorProtocol {
        CreateOperator.infix("-") { (lhs: Double, rhs: Double) in lhs - rhs }
    }

    public static var doubleMultiplyOperator: InfixOperatorProtocol {
        CreateOperator.infix("*") { (lhs: Double, rhs: Double) in lhs * rhs }
    }

    public static var doubleDivideOperator: InfixOperatorProtocol {
        CreateOperator.infix("/") { (lhs: Double, rhs: Double) in rhs != 0 ? lhs / rhs : 0 }
    }

    // MARK: - Arithmetic (Int)

    public static var intAddOperator: InfixOperatorProtocol {
        CreateOperator.infix("+") { (lhs: Int, rhs: Int) in lhs + rhs }
    }

    public static var intSubtractOperator: InfixOperatorProtocol {
        CreateOperator.infix("-") { (lhs: Int, rhs: Int) in lhs - rhs }
    }

    public static var intMultiplyOperator: InfixOperatorProtocol {
        CreateOperator.infix("*") { (lhs: Int, rhs: Int) in lhs * rhs }
    }

    public static var intDivideOperator: InfixOperatorProtocol {
        CreateOperator.infix("/") { (lhs: Int, rhs: Int) in rhs != 0 ? lhs / rhs : 0 }
    }

    // MARK: - Membership

    public static var inDoubleArrayOperator: InfixOperatorProtocol {
        CreateOperator.infix("in") { (lhs: Double, rhs: [Double]) in rhs.contains(lhs) }
    }

    public static var notInDoubleArrayOperator: InfixOperatorProtocol {
        CreateOperator.infix("not-in") { (lhs: Double, rhs: [Double]) in !rhs.contains(lhs) }
    }

    public static var inIntArrayOperator: InfixOperatorProtocol {
        CreateOperator.infix("in") { (lhs: Int, rhs: [Int]) in rhs.contains(lhs) }
    }

    public static var notInIntArrayOperator: InfixOperatorProtocol {
        CreateOperator.infix("not-in") { (lhs: Int, rhs: [Int]) in !rhs.contains(lhs) }
    }

    public static var inStringArrayOperator: InfixOperatorProtocol {
        CreateOperator.infix("in") { (lhs: String, rhs: [String]) in rhs.contains(lhs) }
    }

    public static var notInStringArrayOperator: InfixOperatorProtocol {
        CreateOperator.infix("not-in") { (lhs: String, rhs: [String]) in !rhs.contains(lhs) }
    }

    // MARK: - Logical

    public static var andOperator: InfixOperatorProtocol {
        CreateOperator.infix("and") { (lhs: Bool, rhs: Bool) in lhs && rhs }
    }

    public static var orOperator: InfixOperatorProtocol {
        CreateOperator.infix("or") { (lhs: Bool, rhs: Bool) in lhs || rhs }
    }

}
