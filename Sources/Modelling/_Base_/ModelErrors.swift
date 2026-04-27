//
//  Model_ParsingError.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum Model_ParsingError: ErrorWithMessageAndParsedInfo, ErrorCodeProviding {
    case objectTypeNotFound(String, ParsedInfo)
    case invalidPropertyInType(String, ParsedInfo)
    case invalidPropertyUsedInApi(String, ParsedInfo)
    case invalidMapping(String, ParsedInfo)
    case invalidPropertyLine(ParsedInfo)
    /// `@constraintName` appears outside `{ }`; must be moved into the constraint block.
    case propertyConstraintReferenceOutsideBlock(refs: [String], ParsedInfo)
    case invalidMethodLine(ParsedInfo)
    case invalidDerivedProperty(String, ParsedInfo)
    case invalidContainerMemberLine(ParsedInfo)
    case invalidContainerLine(ParsedInfo)
    case invalidModuleLine(ParsedInfo)
    case invalidSubModuleLine(ParsedInfo)
    case invalidDomainObjectLine(ParsedInfo)
    case invalidDtoObjectLine(ParsedInfo)
    case invalidUIViewLine(ParsedInfo)
    case invalidFlowLine(ParsedInfo)
    case invalidRulesLine(ParsedInfo)
    case invalidPrintableLine(ParsedInfo)
    case invalidConfigLine(ParsedInfo)
    case invalidHierarchyLine(ParsedInfo)
    case invalidAgentLine(ParsedInfo)
    case invalidAnnotationLine(ParsedInfo)
    case invalidAttachedSection(ParsedInfo)
    case invalidApiLine(ParsedInfo)
    case invalidSystemLine(ParsedInfo)
    case invalidCodeLogicStatement(String, ParsedInfo)
    /// A tag was written with empty parentheses — e.g. `#blueprint()`. Either supply an argument or omit the parens.
    case invalidTagArgument(String, ParsedInfo)

    public var info: String {
        switch self {
        case .objectTypeNotFound(let message, _): return message
        case .invalidPropertyInType(let message, _): return message
        case .invalidPropertyUsedInApi(let message, _): return message
        case .invalidPropertyLine(let pInfo): return "invalid property: \(pInfo.line)"
        case .propertyConstraintReferenceOutsideBlock(let refs, _):
            let list = refs.map { "@\($0)" }.joined(separator: ", ")
            return
                "Named constraint reference(s) \(list) must appear inside the { } constraint block, not outside. Move \(list) into { ... }."
        case .invalidDerivedProperty(let msg, _): return "invalid derived property: \(msg)"
        case .invalidMethodLine(let pInfo): return "invalid method: \(pInfo.line)"

        case .invalidMapping(let mapping, _): return "invalid mapping: \(mapping)"
        case .invalidAnnotationLine(let pInfo):
            return "invalid annotation: \(pInfo.line)"

        case .invalidSystemLine(let pInfo): return "invalid system: \(pInfo.line)"
        case .invalidContainerLine(let pInfo): return "invalid container: \(pInfo.line)"
        case .invalidContainerMemberLine(let pInfo):
            return "invalid container member: \(pInfo.line)"
        case .invalidModuleLine(let pInfo): return "invalid module: \(pInfo.line)"
        case .invalidSubModuleLine(let pInfo): return "invalid sub module: \(pInfo.line)"
        case .invalidAttachedSection(let pInfo): return "invalid attached section: \(pInfo.line)"

        case .invalidDomainObjectLine(let pInfo): return "invalid domain object: \(pInfo.line)"
        case .invalidDtoObjectLine(let pInfo): return "invalid dto object: \(pInfo.line)"
        case .invalidUIViewLine(let pInfo): return "invalid ui view: \(pInfo.line)"
        case .invalidFlowLine(let pInfo): return "invalid flow: \(pInfo.line)"
        case .invalidRulesLine(let pInfo): return "invalid rules: \(pInfo.line)"
        case .invalidPrintableLine(let pInfo): return "invalid printable: \(pInfo.line)"
        case .invalidConfigLine(let pInfo): return "invalid config: \(pInfo.line)"
        case .invalidHierarchyLine(let pInfo): return "invalid hierarchy: \(pInfo.line)"
        case .invalidAgentLine(let pInfo): return "invalid agent: \(pInfo.line)"

        case .invalidApiLine(let pInfo): return "invalid api: \(pInfo.line)"
        case .invalidCodeLogicStatement(let message, _): return message
        case .invalidTagArgument(let tag, _): return "#\(tag)() has empty parentheses — supply an argument or remove the parentheses"
        }
    }

    public var diagnosticErrorCode: DiagnosticErrorCode {
        switch self {
        case .objectTypeNotFound: return .e601
        case .invalidPropertyInType: return .e602
        case .invalidPropertyUsedInApi: return .e603
        case .invalidMapping: return .e604
        case .invalidPropertyLine: return .e605
        case .propertyConstraintReferenceOutsideBlock: return .e620
        case .invalidMethodLine: return .e606
        case .invalidDerivedProperty: return .e607
        case .invalidContainerMemberLine: return .e608
        case .invalidContainerLine: return .e609
        case .invalidModuleLine: return .e610
        case .invalidSubModuleLine: return .e611
        case .invalidDomainObjectLine: return .e612
        case .invalidDtoObjectLine: return .e613
        case .invalidUIViewLine: return .e614
        case .invalidFlowLine: return .e614
        case .invalidRulesLine: return .e614
        case .invalidPrintableLine: return .e614
        case .invalidConfigLine: return .e614
        case .invalidHierarchyLine: return .e614
        case .invalidAgentLine: return .e614
        case .invalidAnnotationLine: return .e615
        case .invalidAttachedSection: return .e616
        case .invalidApiLine: return .e617
        case .invalidSystemLine: return .e619
        case .invalidCodeLogicStatement: return .e618
        case .invalidTagArgument: return .e621
        }
    }

    public var pInfo: ParsedInfo {
        return switch self {
        case .objectTypeNotFound(_, let pInfo): pInfo
        case .invalidPropertyInType(_, let pInfo): pInfo
        case .invalidPropertyUsedInApi(_, let pInfo): pInfo
        case .invalidPropertyLine(let pInfo): pInfo
        case .propertyConstraintReferenceOutsideBlock(_, let pInfo): pInfo
        case .invalidDerivedProperty(_, let pInfo): pInfo
        case .invalidMethodLine(let pInfo): pInfo

        case .invalidMapping(_, let pInfo): pInfo
        case .invalidAnnotationLine(let pInfo): pInfo

        case .invalidSystemLine(let pInfo): pInfo
        case .invalidContainerLine(let pInfo): pInfo
        case .invalidContainerMemberLine(let pInfo): pInfo
        case .invalidModuleLine(let pInfo): pInfo
        case .invalidSubModuleLine(let pInfo): pInfo
        case .invalidAttachedSection(let pInfo): pInfo

        case .invalidDomainObjectLine(let pInfo): pInfo
        case .invalidDtoObjectLine(let pInfo): pInfo
        case .invalidUIViewLine(let pInfo): pInfo
        case .invalidFlowLine(let pInfo): pInfo
        case .invalidRulesLine(let pInfo): pInfo
        case .invalidPrintableLine(let pInfo): pInfo
        case .invalidConfigLine(let pInfo): pInfo
        case .invalidHierarchyLine(let pInfo): pInfo
        case .invalidAgentLine(let pInfo): pInfo

        case .invalidApiLine(let pInfo): pInfo
        case .invalidCodeLogicStatement(_, let pInfo): pInfo
        case .invalidTagArgument(_, let pInfo): pInfo
        }
    }
}
