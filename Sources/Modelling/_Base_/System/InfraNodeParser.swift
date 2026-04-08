//
//  InfraNodeParser.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//
//  Parses an infra-node setext header inside a system body:
//
//      PostgreSQL [database] #primary-db -- Main relational store
//      ++++++++++++++++++++++++++++++++++
//      host    = db.internal
//      port    = 5432
//      version = 14
//

import Foundation
import RegexBuilder

public enum InfraNodeParser {

    // MARK: - Regex

    /// Captures: (fullMatch, name, optional infraType, optional tagString)
    /// e.g. `Kafka Events [message-broker] #async -- desc`
    nonisolated(unsafe)
        private static let infraHeader: Regex<(Substring, String, String?, String?)> = Regex {
            // name (stops before `[`, `(`, `#`, `--`, `//`)
            Capture {
                OneOrMore {
                    NegativeLookahead {
                        ChoiceOf {
                            "["
                            "#"
                            "("
                            "//"
                            " -- "
                        }
                    }
                    CharacterClass.any
                }
            } transform: {
                String($0).trim()
            }

            // optional [type]
            Optionally {
                ZeroOrMore(.whitespace)
                "["
                Capture {
                    OneOrMore {
                        NegativeLookahead { "]" }
                        CharacterClass.any
                    }
                } transform: {
                    String($0).trim()
                }
                "]"
            }

            // optional #tags block
            Optionally {
                Capture {
                    ModelRegEx.tags
                } transform: {
                    String($0)
                }
            }

            // consume trailing comments silently
            CommonRegEx.comments
        }

    // MARK: - canParse

    /// Returns `true` when the current line is an infra-node header (a non-empty line
    /// that is not a `+` container-ref or asterism) and the next line is an all-`+` underline.
    public static func canParse(parser lineParser: LineParser) async -> Bool {
        let currentLine = await lineParser.currentLine()
        let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.isNotEmpty else { return false }

        // Must not be a container-ref (`+ Name`) or an asterism (`* * *`)
        guard !trimmed.hasPrefix(ModelConstants.Container_Member + " ") else { return false }
        guard !SystemParser.isAsterismLine(trimmed) else { return false }
        // Must not be an annotation or an attached-section/tag line
        guard !trimmed.hasPrefix(ModelConstants.Annotation_Start) else { return false }
        guard !trimmed.hasPrefix(ModelConstants.AttachedSection) else { return false }

        // Name must start with a letter or underscore — guards against `[type]`-only lines,
        // `(attr)` lines, and other non-identifier prefixes that would fail the regex.
        guard let firstChar = trimmed.first, firstChar.isLetter || firstChar == "_" else {
            return false
        }

        let nextLine = await lineParser.lookAheadLine(by: 1)
        let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
        return nextTrimmed.hasOnly(ModelConstants.InfraNodeUnderlineChar) && nextTrimmed.isNotEmpty
    }

    // MARK: - parse

    /// Parses an infra-node block. Expects the parser on the name line.
    /// Consumes the name line, the `++++` underline, and all following `key = value` lines.
    /// Stops (without consuming) on blank lines, asterism lines, or lines that don't look like
    /// `key = value` pairs, leaving the parser positioned on the first non-property line.
    public static func parse(parser: LineParser) async -> InfraNode? {
        var headerLine = await parser.currentLine()

        // Extract inline description (` -- text` suffix)
        let inlineDesc = ParserUtil.extractInlineDescription(from: &headerLine)

        guard let match = headerLine.wholeMatch(of: infraHeader) else { return nil }
        let (_, nodeName, infraType, tagString) = match.output

        let tags = tagString.map { ParserUtil.parseTags(from: $0) } ?? []
        var node = InfraNode(
            givenname: nodeName, infraType: infraType, description: inlineDesc, tags: tags)

        await parser.skipLine()  // skip name line
        await parser.skipLine()  // skip `++++` underline

        // Read `key = value` property lines
        while await parser.linesRemaining {
            let raw = await parser.currentLine()
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // Stop at blank lines, asterisms, or the next infra-node header (lookahead)
            if trimmed.isEmpty { break }
            if trimmed.hasPrefix("//") {
                await parser.skipLine()
                continue
            }
            if SystemParser.isAsterismLine(trimmed) { break }
            if trimmed.hasPrefix(ModelConstants.Container_Member) { break }

            // Must look like `key = value`
            guard let eqRange = trimmed.range(of: "=") else { break }
            let key = String(trimmed[..<eqRange.lowerBound]).trim()
            let value = String(trimmed[eqRange.upperBound...]).trim()
            guard key.isNotEmpty else { break }

            node.properties.append(InfraProperty(key: key, value: value))
            await parser.skipLine()
        }

        return node
    }
}
