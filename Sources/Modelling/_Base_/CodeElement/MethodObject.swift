//
//  MethodObject.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor MethodObject: CodeMember {
    public let pInfo: ParsedInfo
    public var attribs = Attributes()
    public var tags = Tags()

    public var name: String
    public var givenname: String
    public var returnType: TypeInfo
    public var parameters: [MethodParameter] = []

    /// Structured pipe-gutter logic body parsed from the DSL, if present.
    public var logic: CodeLogic?

    public var comment: String?

    /// Returns `true` when the current line is a method signature in either supported style:
    ///   - **Parameter metadata**: one or more `>>>` prefix lines whose first non-`>>>` successor
    ///     is a valid tilde or setext method signature.
    ///   - **Setext**: plain `methodName(...)` or paramless `methodName` with the next line being a method underline.
    ///   - **Tilde**: `~ methodName(...)` or paramless `~ methodName` (no underline line required).
    public static func canParse(parser: any LineParser) async -> Bool {
        let line = await parser.currentLine()

        // Resolve the candidate signature line and its lookahead offset.
        // For a >>> block: scan past all >>> lines (offset 1+).
        // For any other line: it is the signature itself at offset 0.
        let signatureLine: String
        let signatureOffset: Int
        if line.hasPrefix(ModelConstants.Member_ParameterMetadata) {
            let (ahead, offset) = await parser.lookAheadLine(skippingPrefix: ModelConstants.Member_ParameterMetadata)
            if ahead.isEmpty { return false }
            (signatureLine, signatureOffset) = (ahead, offset)
        } else {
            (signatureLine, signatureOffset) = (line, 0)
        }

        // Tilde and setext underline checks performed once against the resolved signature line.
        if isTildePrefixed(signatureLine) { return true }
        let underline = await parser.lookAheadLine(by: signatureOffset + 1)
        return !underline.isEmpty && underline.hasOnly(ModelConstants.MethodUnderlineChar)
    }

    /// Parses the current line (or a block of `>>>` metadata lines + signature) as a method.
    ///
    /// **Parameter metadata style** — zero or more `>>>` prefix lines immediately before the signature:
    /// ```
    /// >>> * paramName: Type = default { constraints } (attributes) #tags
    /// ~ methodName(paramName: Type) : ReturnType
    /// ```
    ///
    /// **Setext style** (two DSL lines consumed, logic fenced with `~~~`):
    /// ```
    /// methodName(param: Type) : ReturnType
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ```
    /// ```
    /// methodName
    /// ----------
    /// ```
    /// **Tilde style** (one DSL line consumed, logic fenced with ` ``` `, `'''`, or `"""`):
    /// ```
    /// ~ methodName(param: Type) : ReturnType
    /// ```
    /// ```
    /// ~ methodName
    /// ```
    /// In both cases, any immediately following logic block is also parsed when `skipLine` is `true`.
    public static func parse(pInfo: ParsedInfo, skipLine: Bool = true) async throws -> MethodObject? {
        // Phase 1: consume all >>> parameter metadata lines preceding the signature.
        // Only enter this path when the current pInfo.line is itself a >>> line; otherwise
        // pInfo.line may have been pre-processed by the caller (e.g. APISectionParser strips
        // the ## prefix before calling us), so we must honour it as-is.
        let collectedMetadata: [String: ParameterMetadata]
        let signatureSource: String

        if pInfo.line.hasPrefix(ModelConstants.Member_ParameterMetadata) {
            collectedMetadata = await ParameterMetadata.parseMetadataBlockIfAny(from: pInfo.parser)
            signatureSource = await pInfo.parser.currentLine()
        } else {
            // No >>> lines; use pInfo.line directly (caller may have stripped a prefix already).
            collectedMetadata = [:]
            signatureSource = pInfo.line
        }

        // Phase 2: parse the actual method signature.
        let line = signatureSource
        let tilde = isTildePrefixed(line)
        let signatureLine = tilde ? String(line.dropFirst()).trim() : line

        guard let signature = parseSignature(signatureLine) else { return nil }

        let givenName = signature.name.trim()

        let method = MethodObject(givenName, pInfo: pInfo)

        let matches = signature.arguments.matches(of: CommonRegEx.namedParameters_Capturing)

        for match in matches {
            let (_, name, typeName) = match.output
            let type = TypeInfo.parse(typeName)
            let param = MethodParameter(
                name: name,
                type: type,
                metadata: collectedMetadata[name] ?? ParameterMetadata()
            )
            await method.append(parameter: param)
        }

        if let returnType = signature.returnType {
            await method.returnType(from: returnType)
        }

        if let attributeString = signature.attributeString {
            await ParserUtil.populateAttributes(for: method, from: attributeString)
        }

        //check if has tags
        if let tagString = signature.tagString {
            await ParserUtil.populateTags(for: method, from: tagString)
        }

        if skipLine {
            // Tilde style has no underline line; setext style has signature + underline.
            await pInfo.parser.skipLine(by: tilde ? 1 : 2)
            if tilde {
                try await method.parseTildeLogicIfPresent(from: pInfo.parser)
            } else {
                try await method.parseSetextLogicIfPresent(from: pInfo.parser)
            }
        }

        return method
    }

    private struct ParsedMethodSignature {
        let name: String
        let arguments: String
        let returnType: String?
        let attributeString: String?
        let tagString: String?
    }

    private static func parseSignature(_ line: String) -> ParsedMethodSignature? {
        if let match = line.wholeMatch(of: ModelRegEx.method_Capturing) {
            let (_, methodName, arguments, returnType, attributeString, tagString) = match.output
            return ParsedMethodSignature(
                name: methodName,
                arguments: arguments,
                returnType: returnType,
                attributeString: attributeString,
                tagString: tagString
            )
        }

        guard let match = line.wholeMatch(of: ModelRegEx.methodParamless_Capturing) else {
            return nil
        }

        let (_, methodName, returnType, attributeString, tagString) = match.output
        return ParsedMethodSignature(
            name: methodName,
            arguments: "",
            returnType: returnType,
            attributeString: attributeString,
            tagString: tagString
        )
    }

    /// Returns `true` when `line` begins with the `~` method prefix but is not a UIView
    /// underline (i.e. not a line composed entirely of `~` characters).
    private static func isTildePrefixed(_ line: String) -> Bool {
        line.hasPrefix(ModelConstants.Member_Method) && !line.hasOnly(ModelConstants.Member_Method)
    }

    public func returnType(from typeName: String) {
        self.returnType = TypeInfo.parse(typeName)
    }

    public func setLogic(_ value: CodeLogic) {
        self.logic = value
    }

    public var hasLogic: Bool { logic != nil && !(logic?.isEmpty ?? true) }

    /// **Setext style** — logic body starts immediately after the `~~~~~~` underline.
    /// No opening `~~~` fence; closing `~~~` is required to end the block.
    public func parseSetextLogicIfPresent(from parser: any LineParser) async throws {
        while await parser.linesRemaining {
            if await parser.isCurrentLineEmptyOrCommented() { await parser.skipLine(); continue }
            break
        }
        guard await parser.linesRemaining else { return }
        if let logic = try await CodeLogicParser.parseFenced(from: parser, pInfo: pInfo, closingFence: CodeLogicParser.setextFenceDelimiter) {
            self.logic = logic
        }
    }

    /// **Tilde-prefix style** — an explicit opening fence is required.
    /// Supported fence styles: ` ``` `, `'''`, or `"""`.
    /// If none is present, the method has no logic body.
    /// The closing fence must match the opening fence.
    public func parseTildeLogicIfPresent(from parser: any LineParser) async throws {
        while await parser.linesRemaining {
            if await parser.isCurrentLineEmptyOrCommented() { await parser.skipLine(); continue }
            break
        }
        guard await parser.linesRemaining else { return }
        guard let fence = CodeLogicParser.tildeFenceDelimiter(for: await parser.currentLine()) else { return }
        await parser.skipLine() // consume opening fence
        if let logic = try await CodeLogicParser.parseFenced(from: parser, pInfo: pInfo, closingFence: fence) {
            self.logic = logic
        }
    }

    public func append(parameter: MethodParameter) async {
        parameters.append(parameter)
    }

    public init(_ name: String, returnType: PropertyKind? = nil, pInfo: ParsedInfo) {
        self.givenname = name.trim()
        self.name = self.givenname.normalizeForVariableName()
        self.returnType = TypeInfo(returnType)
        self.pInfo = pInfo
    }
}

public struct MethodParameter: Sendable {
    public let name: String
    public let type: TypeInfo
    public var metadata: ParameterMetadata

    public init(name: String, type: TypeInfo, metadata: ParameterMetadata = ParameterMetadata()) {
        self.name = name
        self.type = type
        self.metadata = metadata
    }
}

/// Metadata for a method parameter, parsed from `>>>` lines that precede the method signature.
public struct ParameterMetadata: Sendable {
    public var required: RequiredKind
    public var isOutput: Bool
    public var defaultValue: String?
    public var validValueSet: [String]
    public var constraints: [Constraint]
    public var attribs: [Attribute]
    public var tags: [Tag]

    public init(
        required: RequiredKind = .no,
        isOutput: Bool = false,
        defaultValue: String? = nil,
        validValueSet: [String] = [],
        constraints: [Constraint] = [],
        attribs: [Attribute] = [],
        tags: [Tag] = []
    ) {
        self.required = required
        self.isOutput = isOutput
        self.defaultValue = defaultValue
        self.validValueSet = validValueSet
        self.constraints = constraints
        self.attribs = attribs
        self.tags = tags
    }

    /// Consumes all consecutive `>>>` lines at the current parser position and returns a
    /// dictionary keyed by normalised parameter name. Advances the parser past every `>>>` line
    /// it consumes. Returns an empty dictionary (and leaves the parser position unchanged) when
    /// the current line is not a `>>>` line.
    public static func parseMetadataBlockIfAny(from parser: any LineParser) async -> [String: ParameterMetadata] {
        var collected: [String: ParameterMetadata] = [:]
        while await parser.linesRemaining {
            let currentLine = await parser.currentLine()
            guard currentLine.hasPrefix(ModelConstants.Member_ParameterMetadata) else { break }
            if let (name, meta) = parse(from: currentLine) {
                collected[name] = meta
            }
            await parser.skipLine()
        }
        return collected
    }

    /// Parses a single `>>> <marker> <name>: <type> [= default] [{ constraints }] [(attributes)] [#tags]` line.
    /// Returns `(normalizedName, metadata)` or `nil` when the line cannot be parsed.
    public static func parse(from line: String) -> (name: String, metadata: ParameterMetadata)? {
        let prefix = ModelConstants.Member_ParameterMetadata
        guard line.hasPrefix(prefix) else { return nil }

        let afterPrefix = String(line.dropFirst(prefix.count)).trim()
        // afterPrefix: "* paramName: Type [= default] [{ constraints }] [(attributes)] [#tags]"

        guard let marker = afterPrefix.components(separatedBy: .whitespaces).first, !marker.isEmpty else { return nil }
        let propertyLine = String(afterPrefix.dropFirst(marker.count)).trim()
        // propertyLine: "paramName: Type [= default] [{ constraints }] [(attributes)] [#tags]"

        guard let match = propertyLine.wholeMatch(of: ModelRegEx.property_Capturing) else { return nil }
        let (_, propName, _, _, defaultValue, capturedValidValueSet, constraintString, attributeString, tagString) = match.output

        let required: RequiredKind
        switch marker {
        case ModelConstants.Member_PrimaryKey, ModelConstants.Member_Mandatory:
            required = .yes
        default:
            required = .no
        }

        let validValueSet = ParserUtil.parseValidValueSet(from: capturedValidValueSet)

        let constraints = ParserUtil.parseConstraints(from: constraintString)

        let attribs = ParserUtil.parseAttributes(from: attributeString ?? "")
        let tags = ParserUtil.parseTags(from: tagString ?? "")
        let isOutput = tags.contains(where: { $0.name == "output" })

        let name = propName.trim().normalizeForVariableName()
        let metadata = ParameterMetadata(
            required: required,
            isOutput: isOutput,
            defaultValue: defaultValue,
            validValueSet: validValueSet,
            constraints: constraints,
            attribs: attribs,
            tags: tags
        )
        return (name: name, metadata: metadata)
    }
}

public enum ReturnType: Sendable {
    case void, int, double, bool, string
    case customType(String)
}
