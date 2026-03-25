//
//  TemplateSoup_ParsingError.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public enum TemplateSoup_ParsingError: ErrorWithMessageAndParsedInfo, ErrorCodeProviding {
    case invalidFrontMatter(String, ParsedInfo)
    case invalidStmt(ParsedInfo)
    case invalidMultiBlockStmt(ParsedInfo)
    case invalidTemplateFunctionStmt(String, ParsedInfo)
    case modifierNotFound(String, ParsedInfo)
    case modifierInvalidSyntax(String, ParsedInfo)
    case modifierInvalidArguments(String, ParsedInfo)
    case modifierCalledOnwrongType(String, String, ParsedInfo)
    case invalidExpression(String, ParsedInfo)
    case propertiesEmpty(String, ParsedInfo)
    case invalidPropertyAccess(String, ParsedInfo)
    case variableOrPropertyNotFound(String, ParsedInfo)
    case expressionOperandNotFound(String, ParsedInfo)
    case invalidPropertyInCall(String, ParsedInfo)
    case infixOperatorNotFound(String, ParsedInfo)
    case infixOperatorCalledOnwrongLhsType(String, String, ParsedInfo)
    case infixOperatorCalledOnwrongRhsType(String, String, ParsedInfo)
    case templateFunctionNotFound(String, ParsedInfo)

    public var info: String {
        let suffix = ""
        
        switch (self) {
        case .invalidFrontMatter(let line, _) :
            return suffix + "invalid front matter: \(line)"
        case .invalidStmt(let pInfo) :
            return suffix + "invalid stmt: \(pInfo.line)"
        case .invalidMultiBlockStmt(let pInfo) :
            return suffix + "invalid syntax:  \(pInfo.line)"
        case .invalidTemplateFunctionStmt(let line, _) :
            return suffix + "invalid fn definition: \(line)"

        case .modifierNotFound(let message, _) :
            return message  // message already contains suggestions (from Modifiers.parse)
        case .modifierInvalidSyntax(let message, _) :
            return message
        case .modifierInvalidArguments(let modifier, _) :
            return "Invalid modifier arguments: \(modifier)"
        case .modifierCalledOnwrongType(let modifier, let typeName, _) :
            return "Modifier '\(modifier)' cannot be applied to a value of type '\(typeName)'. Expected a compatible input type."

        case .infixOperatorNotFound(let msg, _) :
            return msg
        case .infixOperatorCalledOnwrongLhsType(let infix, let typeName, _) :
            return "Operator '\(infix)' cannot be applied: left-hand side has unexpected type '\(typeName)'."
        case .infixOperatorCalledOnwrongRhsType(let infix, let typeName, _) :
            return "Operator '\(infix)' cannot be applied: right-hand side has unexpected type '\(typeName)'."

        case .invalidExpression(let expn, _) :
            return "Expression syntax error: '\(expn)'"
        case .propertiesEmpty(let msg, _) :
            return msg
        case .invalidPropertyAccess(let msg, _) :
            return msg
        case .variableOrPropertyNotFound(let msg, _) :
            return msg
        case .expressionOperandNotFound(let msg, _) :
            return msg
        case .invalidPropertyInCall(let msg, _) :
            return msg

        case .templateFunctionNotFound(let msg, _) :
            return msg
            
        }
    }

    public var errorCode: String {
        switch self {
        case .invalidFrontMatter: return "E201"
        case .invalidStmt: return "E202"
        case .invalidMultiBlockStmt: return "E203"
        case .invalidTemplateFunctionStmt: return "E204"
        case .modifierNotFound: return "E205"
        case .modifierInvalidSyntax: return "E206"
        case .modifierInvalidArguments: return "E207"
        case .modifierCalledOnwrongType: return "E208"
        case .invalidExpression: return "E209"
        case .propertiesEmpty: return "E210"
        case .invalidPropertyAccess: return "E211"
        case .variableOrPropertyNotFound: return "E212"
        case .expressionOperandNotFound: return "E213"
        case .invalidPropertyInCall: return "E214"
        case .infixOperatorNotFound: return "E215"
        case .infixOperatorCalledOnwrongLhsType: return "E216"
        case .infixOperatorCalledOnwrongRhsType: return "E217"
        case .templateFunctionNotFound: return "E218"
        }
    }

    public var pInfo: ParsedInfo {
        return switch self {
        case .invalidFrontMatter(_, let pInfo) : pInfo
        case .invalidStmt(let pInfo) : pInfo
        case .invalidMultiBlockStmt(let pInfo) : pInfo
        case .invalidTemplateFunctionStmt(_, let pInfo) : pInfo

        case .modifierNotFound(_, let pInfo) : pInfo
        case .modifierInvalidSyntax(_, let pInfo) : pInfo
        case .modifierInvalidArguments(_, let pInfo) : pInfo
        case .modifierCalledOnwrongType(_, _, let pInfo) : pInfo

        case .infixOperatorNotFound(_, let pInfo) : pInfo
        case .infixOperatorCalledOnwrongLhsType(_, _, let pInfo) : pInfo
        case .infixOperatorCalledOnwrongRhsType(_, _, let pInfo) : pInfo

        case .invalidExpression(_, let pInfo) : pInfo
        case .propertiesEmpty(_, let pInfo) : pInfo
        case .invalidPropertyAccess(_, let pInfo) : pInfo
        case .variableOrPropertyNotFound(_, let pInfo) : pInfo
        case .expressionOperandNotFound(_, let pInfo) : pInfo
        case .invalidPropertyInCall(_, let pInfo) : pInfo

        case .templateFunctionNotFound(_, let pInfo) : pInfo
            
        }
    }
}
