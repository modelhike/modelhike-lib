//
//  ParserUtil.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public protocol HasDescription_Actor: Actor {
    var description: String? { get async }
    func setDescription(_ value: String?)
}

public class ParserUtil {

    // MARK: - Descriptions (`--`, `>>>` blocks)

    /// Collects bare `>>>` lines before an element: prose descriptions vs `>>>` parameter metadata lines.
    public struct PendingMetadataBlock: Sendable {
        public var descriptionLines: [String] = []
        public var parameterMetadataLines: [String] = []

        public init() {}

        public var combinedDescription: String? {
            guard !descriptionLines.isEmpty else { return nil }
            return descriptionLines.joined(separator: " ")
        }

        public mutating func clear() {
            descriptionLines = []
            parameterMetadataLines = []
        }

        public var isEmpty: Bool {
            descriptionLines.isEmpty && parameterMetadataLines.isEmpty
        }
    }

    /// Accumulated metadata flowing from the file-level parser to element parsers.
    /// Starts with `description`; add new fields here as the DSL grows.
    public struct PendingMetadata: Sendable {
        public var description: String?

        public init() {}
        public init(description: String?) { self.description = description }

        public var isEmpty: Bool { description == nil }

        public static func from(_ block: PendingMetadataBlock) -> PendingMetadata? {
            let desc = block.combinedDescription
            guard desc != nil else { return nil }
            return PendingMetadata(description: desc)
        }
    }

    /// `true` when `token` is a `>>>` line marker (`*`, `-->`, …), not bare description text.
    public static func isParameterMetadataMarkerToken(_ token: String) -> Bool {
        if token == ModelConstants.Member_Output || token == ModelConstants.Member_InOut { return true }
        if token == ModelConstants.Member_PrimaryKey || token == ModelConstants.Member_Mandatory { return true }
        if token == ModelConstants.Member_Optional || token == ModelConstants.Member_Optional2 { return true }
        if token.starts(with: ModelConstants.Member_Conditional) { return true }
        return false
    }

    /// Splits a raw header string of the form `Name #tags` into the trimmed name and
    /// the raw tag substring (starting with `#`).
    ///
    /// Unlike `containerName_Capturing`, this handles names whose first character is a
    /// digit (e.g. `1st Layer`) or any other character that the standard regex rejects.
    /// The ` -- inline description` suffix should be stripped before calling this
    /// (via `extractInlineDescription`).
    ///
    /// Returns `(name, nil)` when no `#` is present.
    public static func extractNameAndTagString(from line: String) -> (name: String, tagString: String?) {
        let trimmed = line.trim()
        if let hashRange = trimmed.range(of: "#") {
            let name = String(trimmed[..<hashRange.lowerBound].trim())
            let tagStr = String(trimmed[hashRange.lowerBound...])
            return (name, tagStr.isEmpty ? nil : tagStr)
        }
        return (trimmed, nil)
    }

    /// Strips inline ` -- description` from the end of a DSL line (mutates `line`). Returns the description or `nil`.
    public static func extractInlineDescription(from line: inout String) -> String? {
        let trimmed = line.trim()
        guard let range = trimmed.range(of: " -- ") else { return nil }
        let desc = String(trimmed[range.upperBound...].trim())
        line = String(trimmed[..<range.lowerBound].trim())
        return desc.isEmpty ? nil : desc
    }

    /// Consumes consecutive `--` documentation lines (not an all-dash / setext underline line).
    public static func consumeDescriptionLines(from parser: any LineParser) async -> String? {
        var parts: [String] = []
        while await parser.linesRemaining {
            let raw = await parser.currentLine()
            let trimmed = raw.trim()
            guard trimmed.hasPrefix(ModelConstants.Member_Description) else { break }
            if trimmed.hasOnly("-") { break }
            let text = String(trimmed.dropFirst(ModelConstants.Member_Description.count).trim())
            parts.append(text)
            await parser.skipLine()
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    /// Consumes consecutive `>>>` lines into `block`, advancing `parser`. Returns `false` if the current line is not `>>>`.
    public static func consumePendingMetadataBlockLines(from parser: any LineParser, into block: inout PendingMetadataBlock) async -> Bool {
        guard await parser.linesRemaining else { return false }
        let first = await parser.currentLine()
        guard first.hasPrefix(ModelConstants.Member_ParameterMetadata) else { return false }
        while await parser.linesRemaining {
            let line = await parser.currentLine()
            guard line.hasPrefix(ModelConstants.Member_ParameterMetadata) else { break }
            let remainder = String(line.dropFirst(ModelConstants.Member_ParameterMetadata.count).trim())
            let firstToken = String(remainder.prefix(while: { !$0.isWhitespace }))
            if Self.isParameterMetadataMarkerToken(firstToken) {
                block.parameterMetadataLines.append(line)
            } else {
                block.descriptionLines.append(remainder)
            }
            await parser.skipLine()
        }
        return true
    }

    /// Joins two optional description fragments (inline first, then after).
    public static func joinedDescription(_ a: String?, _ b: String?) -> String? {
        switch (a, b) {
        case (nil, nil): return nil
        case let (x?, nil): return x
        case let (nil, y?): return y
        case let (x?, y?): return x + " " + y
        }
    }

    /// Appends `more` onto an actor's existing description, preserving any previous text.
    public static func appendDescription(_ more: String?, to target: any HasDescription_Actor) async {
        guard let more, !more.isEmpty else { return }
        await target.setDescription(joinedDescription(await target.description, more))
    }

    /// Consumes following `--` lines and appends them onto `target.description`.
    public static func appendConsumedDescriptionLines(from parser: any LineParser, to target: any HasDescription_Actor) async {
        await appendDescription(await consumeDescriptionLines(from: parser), to: target)
    }

    /// Appends description text to the last recognized member when possible; otherwise to the owner when no prior member exists.
    public static func appendDescription(_ more: String?, toLastRecognizedMember lastMember: CodeMember?, orOwner owner: any HasDescription_Actor) async {
        if let method = lastMember as? MethodObject {
            await appendDescription(more, to: method)
        } else if let property = lastMember as? Property {
            await appendDescription(more, to: property)
        } else if lastMember == nil {
            await appendDescription(more, to: owner)
        }
    }

    /// Consumes following `--` lines and appends them to the most appropriate target: last recognized member or owner.
    public static func appendConsumedDescriptionLines(from parser: any LineParser, toLastRecognizedMember lastMember: CodeMember?, orOwner owner: any HasDescription_Actor) async {
        await appendDescription(await consumeDescriptionLines(from: parser), toLastRecognizedMember: lastMember, orOwner: owner)
    }

    /// `= name : ...` line where the value after `:` begins with `{` (named constraint, not a computed property).
    public static func isNamedConstraintEqualsLine(line: String, firstWord: String) -> Bool {
        guard firstWord == ModelConstants.Member_Calculated else { return false }
        let rest = line.remainingLine(after: firstWord).trim()
        guard let colon = rest.firstIndex(of: ":") else { return false }
        let after = String(rest[rest.index(after: colon)...].trim())
        return after.hasPrefix("{")
    }

    /// Returns net `{`/`}` balance for `s`; zero means the brace block is complete.
    private static func braceBalance(_ s: String) -> Int {
        s.reduce(0) { partial, ch in
            if ch == "{" { return partial + 1 }
            if ch == "}" { return partial - 1 }
            return partial
        }
    }

    /// Splits `= name : { ...` into the named-constraint identifier and the initial brace block text.
    private static func splitNamedConstraintHeader(from line: String, firstWord: String) -> (name: String, bodyStart: String)? {
        guard firstWord == ModelConstants.Member_Calculated else { return nil }
        let rest = line.remainingLine(after: firstWord).trim()
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let name = String(rest[..<colon]).trim()
        let bodyStart = String(rest[rest.index(after: colon)...]).trim()
        guard !name.isEmpty, bodyStart.hasPrefix("{") else { return nil }
        return (name, bodyStart)
    }

    /// Continues reading lines until the accumulated `{ ... }` block is balanced.
    private static func collectBalancedBraceBlock(startingWith initial: String, from parser: any LineParser) async -> String {
        var parts: [String] = [initial]
        var balance = braceBalance(initial)
        while balance != 0 {
            guard await parser.linesRemaining else { break }
            await parser.skipLine()
            let nextLine = await parser.currentLine()
            balance += braceBalance(nextLine)
            parts.append(nextLine)
        }
        return parts.joined(separator: String.newLine)
    }

    /// Extracts the inner text of the first balanced `{ ... }` block, trimming surrounding whitespace/newlines.
    private static func extractBraceWrappedInnerText(from combined: String) -> String? {
        guard let open = combined.firstIndex(of: "{"),
              let close = combined[open...].lastIndex(of: "}") else { return nil }
        let inner = String(combined[combined.index(after: open)..<close].trim())
        return inner.isEmpty ? nil : inner
    }

    /// Parses `= name : { expr }` with optional multi-line body; optional `--` lines after.
    public static func parseNamedConstraint(from pInfo: ParsedInfo, parser: any LineParser) async throws -> Constraint? {
        guard let header = splitNamedConstraintHeader(from: pInfo.line, firstWord: pInfo.firstWord) else { return nil }
        let combined = await collectBalancedBraceBlock(startingWith: header.bodyStart, from: parser)
        guard let inner = extractBraceWrappedInnerText(from: combined) else { return nil }

        let exprList = try ConstraintParser.parseList(inner)
        guard let expr = exprList.first?.expr else { return nil }

        await parser.skipLine()
        let afterDesc = await consumeDescriptionLines(from: parser)
        return Constraint(name: header.name, expr: expr, description: afterDesc)
    }

    /// Returns `true` when `ch` is valid inside an `@identifier` reference name.
    private static func isAtReferenceIdentifierChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_"
    }

    /// Returns `true` when `@` is embedded inside another token (for example `Reference@Organization`) rather than starting a standalone reference.
    private static func isEmbeddedAtReference(in line: String, at atIndex: String.Index) -> Bool {
        guard atIndex > line.startIndex else { return false }
        let prev = line[line.index(before: atIndex)]
        return isAtReferenceIdentifierChar(prev)
    }

    /// Reads the identifier immediately following `@`, returning the parsed name and the index after it.
    private static func readAtReferenceName(in line: String, startingAt atIndex: String.Index) -> (name: String, nextIndex: String.Index)? {
        let nameStart = line.index(after: atIndex)
        var nameEnd = nameStart
        while nameEnd < line.endIndex, isAtReferenceIdentifierChar(line[nameEnd]) {
            line.formIndex(after: &nameEnd)
        }
        guard nameEnd > nameStart else { return nil }
        return (String(line[nameStart..<nameEnd]), nameEnd)
    }

    /// Returns `true` when the parsed `@identifier` is immediately followed by annotation syntax (`::`) rather than a reference.
    private static func hasAnnotationSplit(in line: String, afterIdentifierEndingAt index: String.Index) -> Bool {
        guard index < line.endIndex else { return false }
        return line[index...].hasPrefix(ModelConstants.Annotation_Split)
    }

    /// Returns the range of the first balanced delimiter pair, including nested occurrences.
    private static func rangeOfFirstBalancedBlock(in line: String, opening: Character, closing: Character) -> Range<String.Index>? {
        guard let open = line.firstIndex(of: opening) else { return nil }
        var depth = 0
        var i = open
        while i < line.endIndex {
            let ch = line[i]
            if ch == opening {
                depth += 1
            } else if ch == closing {
                depth -= 1
                if depth == 0 {
                    return open..<line.index(after: i)
                }
            }
            line.formIndex(after: &i)
        }
        return nil
    }

    /// `@identifier` tokens on a property line (skips annotation-style `word::`).
    /// Ignores `@` immediately after a letter, digit, or `_` (e.g. `Reference@Organization` type syntax).
    public static func extractAtReferences(from line: String) -> [String] {
        var out: [String] = []
        var i = line.startIndex
        let atMarker = Character(ModelConstants.Annotation_Start)
        while i < line.endIndex {
            guard line[i] == atMarker else {
                line.formIndex(after: &i)
                continue
            }
            if isEmbeddedAtReference(in: line, at: i) {
                line.formIndex(after: &i)
                continue
            }
            guard let ref = readAtReferenceName(in: line, startingAt: i) else {
                line.formIndex(after: &i)
                continue
            }
            if hasAnnotationSplit(in: line, afterIdentifierEndingAt: ref.nextIndex) {
                i = ref.nextIndex
                continue
            }
            out.append(ref.name)
            i = ref.nextIndex
        }
        return out
    }

    /// Range of the first `{ ... }` on the line, with nested `{` / `}` balanced.
    public static func rangeOfFirstBalancedBraceBlock(in line: String) -> Range<String.Index>? {
        rangeOfFirstBalancedBlock(in: line, opening: "{", closing: "}")
    }

    /// Returns the line with the first balanced `{ ... }` removed (constraint block), for scanning `@` outside `{ }`.
    public static func lineByRemovingFirstBalancedBraceBlock(_ line: String) -> String {
        guard let r = rangeOfFirstBalancedBraceBlock(in: line) else { return line }
        var s = line
        s.removeSubrange(r)
        return s
    }

    /// `@name` entries for `Property.appliedConstraints` must appear only inside `{ ... }`.
    /// `= @ExpressionName` (default) may appear outside. Throws if any other `@ref` is outside `{ }`.
    /// - Parameters:
    ///   - outsideConstraintBlock: Property remainder **after** `lineByRemovingFirstBalancedBraceBlock` — scans for stray `@` (E620). Not replaceable by `constraintInner` alone (that is only inside `{ }`).
    ///   - constraintInner: Captured inner text of `{ ... }`; collects `appliedConstraints` names.
    public static func appliedConstraintNamesFromPropertySignature(outsideConstraintBlock: String, constraintInner: String?, appliedDefaultExpression: String?, pInfo: ParsedInfo) throws -> [String] {
        let insideRefs = extractAtReferences(from: constraintInner ?? "")
        let outsideRefs = extractAtReferences(from: outsideConstraintBlock)
        let defaultName = appliedDefaultExpression
        let offending = outsideRefs.filter { ref in defaultName.map { $0 != ref } ?? true }
        if !offending.isEmpty {
            throw Model_ParsingError.propertyConstraintReferenceOutsideBlock(refs: offending, pInfo)
        }
        return insideRefs
    }

    /// Returns a `[String]` array of valid values parsed from `vvsString` (e.g. `"NEW", "ACTIVE"`).
    /// Returns an empty array when `vvsString` is `nil` or empty.
    public static func parseValidValueSet(from vvsString: String?) -> [String] {
        guard let vvsString, !vvsString.isEmpty else { return [] }
        return vvsString.matches(of: CommonRegEx.validValue).map { String($0.output) }
    }

    /// Returns an `[Attribute]` array parsed from `attributeString` without touching any actor.
    public static func parseAttributes(from attributeString: String) -> [Attribute] {
        attributeString.matches(of: ModelRegEx.attributes_Capturing).map { match in
            let (_, key, value) = match.output
            let k = key.trim()
            return Attribute(key: k.lowercased(), givenKey: k, value: value ?? k)
        }
    }

    /// Parses attributes from `attributeString` and applies them directly onto an actor-backed artifact.
    public static func populateAttributes(for artifact: HasAttributes_Actor, from attributeString: String) async {
        let attribMatches = attributeString.matches(of: ModelRegEx.attributes_Capturing)
        
        for match in attribMatches {
            let (_, name, value) = match.output
            
            if let value = value { // key-value attribute
                await artifact.attribs.set(name.trim(), value: value)
            } else {
                //add the key as value
                await artifact.attribs.set(name.trim(), value: name.trim())
            }
        }
    }

    /// Returns a `[Constraint]` array parsed from `constraintString` without touching any actor.
    /// Returns an empty array when `constraintString` is `nil`, empty, or malformed.
    public static func parseConstraints(from constraintString: String?) -> [Constraint] {
        guard let constraintString, !constraintString.isEmpty else { return [] }
        return (try? ConstraintParser.parseList(constraintString)) ?? []
    }

    /// Parses inline property constraints and stores them on the target property actor.
    public static func populateConstraints(for property: Property, from constraintString: String) async {
        await property.constraints.set(parseConstraints(from: constraintString))
    }
    
    /// Returns a `[Tag]` array parsed from `tagString` without touching any actor.
    public static func parseTags(from tagString: String) -> [Tag] {
        tagString.matches(of: ModelRegEx.tags_Capturing).map { match in
            let (_, tagName, arg) = match.output
            return arg != nil ? Tag(tagName, arg: arg!) : Tag(tagName)
        }
    }

    /// Parses tags from `tagString` and appends them onto an actor-backed artifact.
    public static func populateTags(for artifact: HasTags_Actor, from tagString: String) async {
        let tagMatches = tagString.matches(of: ModelRegEx.tags_Capturing)
        
        for match in tagMatches {
            let (_, tag, arg) = match.output
            
            if let arg = arg {
                await artifact.tags.append(tag, arg: arg)
            } else {
                await artifact.tags.append(tag)
            }
        }
    }
    
    /// Resolves mixin-like references from attributes/tags into actual model types and appends them to `artifact`.
    public static func extractMixins(for artifact: CodeObject, with ctx: LoadContext) async throws {
        let item = artifact
        try await item.attribs.processEach { attrib in
            if let entity = await ctx.model.types.get(for: attrib.name) {
                await item.append(mixin: entity)
                return nil //remove from attributes, as it is added to mixins
            }
            return attrib
        }
        
        try await item.tags.processEach { tag in
            if tag == TagConstants.savedFrom, let arg = tag.arg {
                if let entity = await ctx.model.types.get(for: arg) {
                    await item.append(mixin: entity)
                }
                return tag
            } else {
                return tag
            }
        }
    }
}

extension MethodObject: HasDescription_Actor {}
extension Property: HasDescription_Actor {}
extension DomainObject: HasDescription_Actor {}
extension DtoObject: HasDescription_Actor {}
extension UIView: HasDescription_Actor {}
extension C4Component: HasDescription_Actor {}
extension C4Container: HasDescription_Actor {}
extension C4System: HasDescription_Actor {}
extension AttachedSection: HasDescription_Actor {}

