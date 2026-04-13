//
//  ParsingError.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum ParsingError: ErrorWithMessageAndParsedInfo, ErrorCodeProviding {
    case invalidLine(ParsedInfo, ErrorWithMessage)
    //case invalidLineWithInfo_HavingLineno(ParsedInfo, ErrorWithMessage)
    case invalidLineWithoutErr(String, ParsedInfo)
    case unrecognisedParsingDirective(String, ParsedInfo)
    case invalidParsingDirective(ParsedInfo)
    case featureNotImplementedYet(ParsedInfo)

    public var info: String {
        switch self {
        case .invalidLine(_, let err):
            return err.info
        //            case .invalidLineWithInfo_HavingLineno(let pInfo, let err) :
        //            return "🐞🐞 \(pInfo.identifier) >> \(err.info)"
        case .invalidLineWithoutErr(let info, _):
            return info
        case .unrecognisedParsingDirective(let directiveName, _):
            return "Unrecognised Parsing Directive '\(directiveName)'"
        case .invalidParsingDirective(let pInfo):
            return "invalid Parsing Directive '\(pInfo.line)"
        case .featureNotImplementedYet(let pInfo):
            return "Feature not implemented yet: \(pInfo.line)"
        }
    }

    public var diagnosticErrorCode: DiagnosticErrorCode {
        switch self {
        case .invalidLine(_, let err):
            return err.diagnosticErrorCode ?? .e401
        case .invalidLineWithoutErr:
            return .e402
        case .unrecognisedParsingDirective:
            return .e403
        case .invalidParsingDirective:
            return .e404
        case .featureNotImplementedYet:
            return .e405
        }
    }

    public var pInfo: ParsedInfo {
        return switch self {
        case .invalidLine(let pInfo, _): pInfo
        //case .invalidLineWithInfo_HavingLineno(let pInfo, let err) : pInfo
        case .invalidLineWithoutErr(_, let pInfo): pInfo
        case .unrecognisedParsingDirective(_, let pInfo): pInfo
        case .invalidParsingDirective(let pInfo): pInfo
        case .featureNotImplementedYet(let pInfo): pInfo
        }
    }

}
