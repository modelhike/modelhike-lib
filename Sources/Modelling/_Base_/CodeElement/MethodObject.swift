//
//  MethodObject.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
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
    /// Documentation from `--` or bare `>>>` blocks before the method.
    public private(set) var description: String?

    public func setDescription(_ value: String?) {
        self.description = value
    }

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
        return underline.isNotEmpty && underline.hasOnly(ModelConstants.MethodUnderlineChar)
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
    public static func parse(pInfo: ParsedInfo, pendingMetadataBlock: ParserUtil.PendingMetadataBlock? = nil, skipLine: Bool = true) async throws -> MethodObject? {
        // Phase 1: `>>>` block — either pre-collected (`pendingMetadataBlock`) or consumed here.
        let collectedMetadata: [String: ParameterMetadata]
        let blockDescription: String?
        let signatureSource: String

        if let pending = pendingMetadataBlock {
            collectedMetadata = ParameterMetadata.metadataDict(from: pending.parameterMetadataLines)
            blockDescription = pending.combinedDescription
            signatureSource = pInfo.line
        } else if pInfo.line.hasPrefix(ModelConstants.Member_ParameterMetadata) {
            let parsed = await ParameterMetadata.parseMetadataBlockIfAny(from: pInfo.parser)
            collectedMetadata = parsed.metadata
            blockDescription = parsed.blockDescription
            signatureSource = await pInfo.parser.currentLine()
        } else {
            collectedMetadata = [:]
            blockDescription = nil
            signatureSource = pInfo.line
        }

        // Phase 2: parse the actual method signature.
        var line = signatureSource
        let inlineSigDesc = ParserUtil.extractInlineDescription(from: &line)
        let tilde = isTildePrefixed(line)
        let signatureLine = tilde ? String(line.dropFirst().trim()) : line

        guard let signature = parseSignature(signatureLine) else { return nil }

        let givenName = signature.name.trim()

        let method = MethodObject(givenName, pInfo: pInfo)

        if let mergedDesc = ParserUtil.joinedDescription(blockDescription, inlineSigDesc) {
            await method.setDescription(mergedDesc)
        }

        let argSegments = Self.splitTopLevelCommas(signature.arguments)
        for segment in argSegments {
            guard let parsed = Self.parseMethodArgumentSegment(segment) else { continue }
            let nameKey = parsed.name.normalizeForVariableName()
            let meta = collectedMetadata[nameKey] ?? parsed.metadata
            let param = MethodParameter(name: parsed.name, type: parsed.type, metadata: meta)
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

    private struct NestedDelimiterDepth {
        var paren = 0
        var angle = 0
        var bracket = 0

        var isTopLevel: Bool {
            paren == 0 && angle == 0 && bracket == 0
        }

        mutating func update(for ch: Character) {
            switch ch {
            case "(":
                paren += 1
            case ")":
                paren = max(0, paren - 1)
            case "<":
                angle += 1
            case ">":
                angle = max(0, angle - 1)
            case "[":
                bracket += 1
            case "]":
                bracket = max(0, bracket - 1)
            default:
                break
            }
        }
    }

    /// Splits a method parameter list on commas not inside `()`, `<>`, or `[]`.
    private static func splitTopLevelCommas(_ raw: String) -> [String] {
        let s = raw.trim()
        guard s.isNotEmpty else { return [] }
        var parts: [String] = []
        var depth = NestedDelimiterDepth()
        var current = ""

        func appendCurrentIfNonEmpty() {
            let piece = current.trim()
            if piece.isNotEmpty {
                parts.append(piece)
            }
            current = ""
        }

        for ch in s {
            if ch == ",", depth.isTopLevel {
                appendCurrentIfNonEmpty()
                continue
            }
            depth.update(for: ch)
            current.append(ch)
        }
        appendCurrentIfNonEmpty()
        return parts
    }

    /// Parses one method argument: optional `-->` / `<-->`, `name : Type`, optional `= default`.
    private static func parseMethodArgumentSegment(_ segment: String) -> (name: String, type: TypeInfo, metadata: ParameterMetadata)? {
        var s = segment.trim()
        guard s.isNotEmpty else { return nil }
        var meta = ParameterMetadata()
        consumeDirectionPrefix(from: &s, metadata: &meta)

        guard let (name, remainder) = splitNameAndRemainder(from: s) else { return nil }
        guard name.isNotEmpty else { return nil }

        let (typeString, defaultValue) = splitTypeAndDefault(from: remainder)
        meta.defaultValue = defaultValue

        let type = TypeInfo.parse(typeString)
        return (name: name, type: type, metadata: meta)
    }

    private static func consumeDirectionPrefix(from segment: inout String, metadata: inout ParameterMetadata) {
        if segment.hasPrefix(ModelConstants.Member_InOut) {
            segment = String(segment.dropFirst(ModelConstants.Member_InOut.count).trim())
            metadata.required = .yes
            metadata.isOutput = true
        } else if segment.hasPrefix(ModelConstants.Member_Output) {
            segment = String(segment.dropFirst(ModelConstants.Member_Output.count).trim())
            metadata.required = .no
            metadata.isOutput = true
        }
    }

    private static func splitNameAndRemainder(from segment: String) -> (name: String, remainder: String)? {
        guard let colon = segment.firstIndex(of: ":") else { return nil }
        let name = String(segment[..<colon]).trim()
        let remainder = String(segment[segment.index(after: colon)...]).trim()
        return (name, remainder)
    }

    private static func splitTypeAndDefault(from remainder: String) -> (typeString: String, defaultValue: String?) {
        let defaultDelimiter = " = "
        guard let eqRange = remainder.range(of: defaultDelimiter) else {
            return (remainder, nil)
        }
        let typeString = String(remainder[..<eqRange.lowerBound]).trim()
        let defaultValue = String(remainder[eqRange.upperBound...]).trim()
        return (typeString, defaultValue)
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

    public var hasLogic: Bool { logic?.isNotEmpty == true }

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
    /// Documentation from `--` on the same `>>>` line as parameter metadata.
    public var description: String?

    public init(
        required: RequiredKind = .no,
        isOutput: Bool = false,
        defaultValue: String? = nil,
        validValueSet: [String] = [],
        constraints: [Constraint] = [],
        attribs: [Attribute] = [],
        tags: [Tag] = [],
        description: String? = nil
    ) {
        self.required = required
        self.isOutput = isOutput
        self.defaultValue = defaultValue
        self.validValueSet = validValueSet
        self.constraints = constraints
        self.attribs = attribs
        self.tags = tags
        self.description = description
    }

    /// Consumes all consecutive `>>>` lines at the current parser position. Bare description lines
    /// (no parameter marker) are concatenated into `blockDescription`.
    public static func parseMetadataBlockIfAny(from parser: any LineParser) async -> (metadata: [String: ParameterMetadata], blockDescription: String?) {
        var collected: [String: ParameterMetadata] = [:]
        var descLines: [String] = []
        let prefix = ModelConstants.Member_ParameterMetadata
        while await parser.linesRemaining {
            let currentLine = await parser.currentLine()
            guard currentLine.hasPrefix(prefix) else { break }
            let remainder = currentLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            let firstToken = String(remainder.prefix(while: { !$0.isWhitespace }))
            if ParserUtil.isParameterMetadataMarkerToken(firstToken) {
                if let (name, meta) = parse(from: currentLine) {
                    collected[name] = meta
                }
            } else {
                descLines.append(remainder)
            }
            await parser.skipLine()
        }
        let blockDescription = descLines.isEmpty ? nil : descLines.joined(separator: " ")
        return (collected, blockDescription)
    }

    /// Parses `>>>` lines that were collected without consuming the parser (e.g. from `PendingMetadataBlock`).
    public static func metadataDict(from lines: [String]) -> [String: ParameterMetadata] {
        var collected: [String: ParameterMetadata] = [:]
        // `PendingMetadataBlock.parameterMetadataLines` is already filtered to metadata-bearing `>>>` lines,
        // so this pass only needs to parse each line and keep the latest entry per normalized name.
        for line in lines {
            if let (name, meta) = parse(from: line) {
                collected[name] = meta
            }
        }
        return collected
    }

    /// Parses a single `>>> <marker> <name>: <type> [= default] [{ constraints }] [(attributes)] [#tags]` line.
    /// Returns `(normalizedName, metadata)` or `nil` when the line cannot be parsed.
    public static func parse(from line: String) -> (name: String, metadata: ParameterMetadata)? {
        let prefix = ModelConstants.Member_ParameterMetadata
        guard line.hasPrefix(prefix) else { return nil }

        let afterPrefix = line.dropFirst(prefix.count).trim()
        // afterPrefix: "* paramName: Type ..." or "--> name: Type ..."

        let marker = String(afterPrefix.prefix(while: { !$0.isWhitespace }))
        guard marker.isNotEmpty else { return nil }
        var propertyLine = afterPrefix.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        let paramDesc = ParserUtil.extractInlineDescription(from: &propertyLine)
        // propertyLine: "paramName: Type [= default] [{ constraints }] [(attributes)] [#tags]"

        guard let match = propertyLine.wholeMatch(of: ModelRegEx.property_Capturing) else { return nil }
        let (_, propName, _, _, defaultValue, capturedValidValueSet, constraintString, attributeString, tagString) = match.output

        let required: RequiredKind
        let isOutputMarker: Bool
        switch marker {
        case ModelConstants.Member_PrimaryKey, ModelConstants.Member_Mandatory:
            required = .yes
            isOutputMarker = false
        case ModelConstants.Member_Output:
            required = .no
            isOutputMarker = true
        case ModelConstants.Member_InOut:
            required = .yes
            isOutputMarker = true
        default:
            required = .no
            isOutputMarker = false
        }

        let validValueSet = ParserUtil.parseValidValueSet(from: capturedValidValueSet)

        let constraints = ParserUtil.parseConstraints(from: constraintString)

        let attribs = ParserUtil.parseAttributes(from: attributeString ?? "")
        let tags = ParserUtil.parseTags(from: tagString ?? "")
        let isOutput = isOutputMarker || tags.contains(where: { $0.name == "output" })

        let name = propName.trim().normalizeForVariableName()
        let metadata = ParameterMetadata(
            required: required,
            isOutput: isOutput,
            defaultValue: defaultValue,
            validValueSet: validValueSet,
            constraints: constraints,
            attribs: attribs,
            tags: tags,
            description: paramDesc
        )
        return (name: name, metadata: metadata)
    }
}

public enum ReturnType: Sendable {
    case void, int, double, bool, string
    case customType(String)
}
