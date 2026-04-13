//
//  EvaluationError.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum EvaluationError: ErrorWithMessageAndParsedInfo, ErrorCodeProviding {
    case invalidLine(ParsedInfo, ErrorWithMessage)
    //case invalidLineWithInfo_HavingLineno(ParsedInfo, ErrorWithMessage)
    case invalidInput(String, ParsedInfo)
    case invalidAppState(String, ParsedInfo)
    case failedWriteOperation(String, ParsedInfo)
    case workingDirectoryNotSet(ParsedInfo, ErrorWithMessage)
    case templateDoesNotExist(ParsedInfo, ErrorWithMessage)
    case scriptFileDoesNotExist(ParsedInfo, ErrorWithMessage)

    case readingError(ParsedInfo, ErrorWithMessage)
    case templateRenderingError(ParsedInfo, ErrorWithMessage)

    public var info: String {
        switch self {
        case .invalidLine(_, let err): return err.info
        //            case .invalidLineWithInfo_HavingLineno(let pInfo, let err) :
        //                return "🐞🐞 \(pInfo.identifier) >> \(err.info)"
        case .invalidInput(let msg, _): return msg
        case .invalidAppState(let msg, _): return msg
        case .failedWriteOperation(let msg, _): return msg
        case .workingDirectoryNotSet(_, let err): return err.info
        case .templateDoesNotExist(_, let err): return err.info
        case .scriptFileDoesNotExist(_, let err): return err.info

        case .readingError(_, let err): return err.info
        case .templateRenderingError(_, let err): return err.info
        }
    }

    public var diagnosticErrorCode: DiagnosticErrorCode {
        switch self {
        case .invalidLine(_, let err):
            return err.diagnosticErrorCode ?? .e501
        case .invalidInput:
            return .e502
        case .invalidAppState:
            return .e503
        case .failedWriteOperation:
            return .e504
        case .workingDirectoryNotSet(_, let err):
            return err.diagnosticErrorCode ?? .e505
        case .templateDoesNotExist(_, let err):
            return err.diagnosticErrorCode ?? .e506
        case .scriptFileDoesNotExist(_, let err):
            return err.diagnosticErrorCode ?? .e507
        case .readingError(_, let err):
            return err.diagnosticErrorCode ?? .e508
        case .templateRenderingError(_, let err):
            return err.diagnosticErrorCode ?? .e509
        }
    }

    public var pInfo: ParsedInfo {
        switch self {
        case .invalidLine(let pInfo, _): pInfo
        //case .invalidLineWithInfo_HavingLineno(let pInfo, _) : pInfo
        case .invalidInput(_, let pInfo): pInfo
        case .invalidAppState(_, let pInfo): pInfo
        case .failedWriteOperation(_, let pInfo): pInfo
        case .workingDirectoryNotSet(let pInfo, _): pInfo
        case .templateDoesNotExist(let pInfo, _): pInfo
        case .scriptFileDoesNotExist(let pInfo, _): pInfo

        case .readingError(let pInfo, _): pInfo
        case .templateRenderingError(let pInfo, _): pInfo
        }
    }
}
