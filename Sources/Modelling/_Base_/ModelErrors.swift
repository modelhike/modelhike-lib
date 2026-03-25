//
//  Model_ParsingError.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public enum Model_ParsingError: ErrorWithMessageAndParsedInfo, ErrorCodeProviding {
    case objectTypeNotFound(String, ParsedInfo)
    case invalidPropertyInType(String, ParsedInfo)
    case invalidPropertyUsedInApi(String, ParsedInfo)
    case invalidMapping(String, ParsedInfo)
    case invalidPropertyLine(ParsedInfo)
    case invalidMethodLine(ParsedInfo)
    case invalidDerivedProperty(String, ParsedInfo)
    case invalidContainerMemberLine(ParsedInfo)
    case invalidContainerLine(ParsedInfo)
    case invalidModuleLine(ParsedInfo)
    case invalidSubModuleLine(ParsedInfo)
    case invalidDomainObjectLine(ParsedInfo)
    case invalidDtoObjectLine(ParsedInfo)
    case invalidUIViewLine(ParsedInfo)
    case invalidAnnotationLine(ParsedInfo)
    case invalidAttachedSection(ParsedInfo)
    case invalidApiLine(ParsedInfo)

    public var info: String {
        switch self {
        case .objectTypeNotFound(let message, _): return message
        case .invalidPropertyInType(let message, _): return message
        case .invalidPropertyUsedInApi(let message, _): return message
        case .invalidPropertyLine(let pInfo): return "invalid property: \(pInfo.line)"
        case .invalidDerivedProperty(let msg, _): return "invalid derived property: \(msg)"
        case .invalidMethodLine(let pInfo): return "invalid method: \(pInfo.line)"

        case .invalidMapping(let mapping, _): return "invalid mapping: \(mapping)"
        case .invalidAnnotationLine(let pInfo):
            return "invalid annotation: \(pInfo.line)"

        case .invalidContainerLine(let pInfo): return "invalid container: \(pInfo.line)"
        case .invalidContainerMemberLine(let pInfo):
            return "invalid container member: \(pInfo.line)"
        case .invalidModuleLine(let pInfo): return "invalid module: \(pInfo.line)"
        case .invalidSubModuleLine(let pInfo): return "invalid sub module: \(pInfo.line)"
        case .invalidAttachedSection(let pInfo): return "invalid attached section: \(pInfo.line)"

        case .invalidDomainObjectLine(let pInfo): return "invalid domain object: \(pInfo.line)"
        case .invalidDtoObjectLine(let pInfo): return "invalid dto object: \(pInfo.line)"
        case .invalidUIViewLine(let pInfo): return "invalid ui view: \(pInfo.line)"

        case .invalidApiLine(let pInfo): return "invalid api: \(pInfo.line)"
        }
    }

    public var errorCode: String {
        switch self {
        case .objectTypeNotFound: return "E601"
        case .invalidPropertyInType: return "E602"
        case .invalidPropertyUsedInApi: return "E603"
        case .invalidMapping: return "E604"
        case .invalidPropertyLine: return "E605"
        case .invalidMethodLine: return "E606"
        case .invalidDerivedProperty: return "E607"
        case .invalidContainerMemberLine: return "E608"
        case .invalidContainerLine: return "E609"
        case .invalidModuleLine: return "E610"
        case .invalidSubModuleLine: return "E611"
        case .invalidDomainObjectLine: return "E612"
        case .invalidDtoObjectLine: return "E613"
        case .invalidUIViewLine: return "E614"
        case .invalidAnnotationLine: return "E615"
        case .invalidAttachedSection: return "E616"
        case .invalidApiLine: return "E617"
        }
    }

    public var pInfo: ParsedInfo {
        return switch self {
        case .objectTypeNotFound(_, let pInfo): pInfo
        case .invalidPropertyInType(_, let pInfo): pInfo
        case .invalidPropertyUsedInApi(_, let pInfo): pInfo
        case .invalidPropertyLine(let pInfo): pInfo
        case .invalidDerivedProperty(_, let pInfo): pInfo
        case .invalidMethodLine(let pInfo): pInfo

        case .invalidMapping(_, let pInfo): pInfo
        case .invalidAnnotationLine(let pInfo): pInfo

        case .invalidContainerLine(let pInfo): pInfo
        case .invalidContainerMemberLine(let pInfo): pInfo
        case .invalidModuleLine(let pInfo): pInfo
        case .invalidSubModuleLine(let pInfo): pInfo
        case .invalidAttachedSection(let pInfo): pInfo

        case .invalidDomainObjectLine(let pInfo): pInfo
        case .invalidDtoObjectLine(let pInfo): pInfo
        case .invalidUIViewLine(let pInfo): pInfo

        case .invalidApiLine(let pInfo): pInfo
        }
    }
}
