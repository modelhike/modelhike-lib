//
//  TemplateSoup_EvaluationError.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum TemplateSoup_EvaluationError: ErrorWithMessageAndParsedInfo, ErrorCodeProviding {
    case objectNotFound(String, ParsedInfo)
    case unIdentifiedStmt(ParsedInfo)
    case errorInExpression(String, ParsedInfo)
    case invalidFileSystemPath(operation: String, argument: String, expression: String, actualType: String, ParsedInfo)
    case workingDirectoryNotSet(ParsedInfo)
    case templateDoesNotExist(String, ParsedInfo)
    case templateReadingError(String, ParsedInfo)
    case scriptFileDoesNotExist(String, ParsedInfo)
    case scriptFileReadingError(String, ParsedInfo)
    case nonSendablePropertyValue(String, ParsedInfo)
    case nonSendableValueFound(String, ParsedInfo)

    public var info: String {
        switch (self) {
        case .workingDirectoryNotSet(_) : return "Working directory is not set."
        case .templateDoesNotExist(let templateName, _) : return "Template '\(templateName)' was not found."
        case .templateReadingError(let templateName, _) : return "Template '\(templateName)' could not be read."
        case .scriptFileDoesNotExist(let scriptName, _) : return "Script file '\(scriptName)' was not found."
        case .scriptFileReadingError(let scriptName, _) : return "Script file '\(scriptName)' could not be read."
        case .objectNotFound(let obj, _) :  return "Object '\(obj)' was not found."
        case .invalidFileSystemPath(let operation, let argument, let expression, let actualType, _) :
            return "Filesystem error in \(operation): '\(argument)' path '\(expression)' expected String, got \(actualType)"
        
        case .nonSendablePropertyValue(let propname, _) :  return "property: \(propname) has non-sendable value"
        case .nonSendableValueFound(let value, _) :  return "value: \(value) is non-sendable"
            
        case .unIdentifiedStmt(let pInfo) :
            var str = "unidentified stmt >>  \(pInfo.line)"

            var modifiedLine = pInfo.line.trim()
            
            if modifiedLine.starts(with: TemplateConstants.stmtKeyWord) {
                modifiedLine = String(modifiedLine.dropFirst())
                modifiedLine = modifiedLine.trim()
                
                if modifiedLine.starts(with: TemplateConstants.templateEndKeyword) {
                    let keyword = modifiedLine.remainingLine(after: TemplateConstants.templateEndKeywordWithHyphen)
                    let msg = "Maybe the matching '\(keyword)' statement was not detected."
                    str += .newLine + msg
                }
            }
            return str
            
        case .errorInExpression(let expn, _) : return expn
        }
    }

    public var errorCode: String {
        switch self {
        case .objectNotFound: return "E301"
        case .unIdentifiedStmt: return "E302"
        case .errorInExpression: return "E303"
        case .invalidFileSystemPath: return "E304"
        case .workingDirectoryNotSet: return "E305"
        case .templateDoesNotExist: return "E306"
        case .templateReadingError: return "E307"
        case .scriptFileDoesNotExist: return "E308"
        case .scriptFileReadingError: return "E309"
        case .nonSendablePropertyValue: return "E310"
        case .nonSendableValueFound: return "E311"
        }
    }
    
    public var pInfo: ParsedInfo {
        return switch (self) {
        case .workingDirectoryNotSet(let pInfo) : pInfo
        case .templateDoesNotExist(_, let pInfo) : pInfo
        case .templateReadingError(_, let pInfo) : pInfo
        case .scriptFileDoesNotExist(_, let pInfo) : pInfo
        case .scriptFileReadingError(_, let pInfo) : pInfo
        case .objectNotFound(_, let pInfo) : pInfo
        case .invalidFileSystemPath(_, _, _, _, let pInfo) : pInfo
        case .unIdentifiedStmt(let pInfo) : pInfo
        case .nonSendablePropertyValue(_, let pInfo) : pInfo
        case .nonSendableValueFound(_, let pInfo) : pInfo
        case .errorInExpression(_, let pInfo) : pInfo
        }
    }

}
