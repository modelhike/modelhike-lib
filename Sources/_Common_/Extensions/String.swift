//
//  String.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

private enum StringRegexCache {
    static let normalizeForVariableName = try! NSRegularExpression(pattern: "[^A-Za-z_0-9]+")
    static let normalizeForPackageName = try! NSRegularExpression(pattern: "[^A-Za-z_.0-9]+")
    static let normalizeForId = try! NSRegularExpression(pattern: "[^A-Za-z_0-9]+")
    static let normalizeForFolderName = try! NSRegularExpression(pattern: "[^A-Za-z0-9]+")

    static let camelAcronym = try! NSRegularExpression(pattern: "([A-Z]+)([A-Z][a-z]|[0-9])", options: [])
    static let camelFullWords = try! NSRegularExpression(pattern: "([a-z])([A-Z]|[0-9])", options: [])
    static let camelDigitsFirst = try! NSRegularExpression(pattern: "([0-9])([A-Z])", options: [])
}

public extension String {
    var isNotEmpty: Bool { !isEmpty }
    var nonEmpty: String? { isEmpty ? nil : self }

    static var empty: String { "" }
    
    func `is`(_ txt: String) -> Bool {
        return self.lowercased() == txt.lowercased()
    }
    
    func isOnly(_ txt: String) -> Bool {
        return self.trim() == txt
    }
    
    func hasOnly(_ txt: String) -> Bool {
        let trimmed = self.trim()
        if trimmed.isEmpty || txt.isEmpty { return false }

        if txt.count == 1, let char = txt.first {
            return trimmed.allSatisfy { $0 == char }
        }

        if trimmed.count % txt.count != 0 { return false }
        let repeatCount = trimmed.count / txt.count
        let comparedString = String(repeating: txt, count: repeatCount)
        return trimmed == comparedString
    }
    
    func hasOnly(_ times: Int, of txt: String) -> Bool {
        let trimmed = self.trim()
        if (trimmed.isEmpty) { return false }

        let comparedString = String(repeating: String(txt), count: times)
        return trimmed == comparedString
    }
    
    func has(prefix: String, filler txt: String, suffix: String) -> Bool {
        if self.hasPrefix(prefix) && self.hasSuffix(suffix) {
            if let filler = between(prefix: prefix, suffix: suffix),
                filler.hasOnly(ModelConstants.NameOverlineChar) {
                return true
            }
        }
        
        return false
    }
    
    func firstWord() -> String? {
        firstAndsecondWord().0
    }
    
    func secondWord() -> String? {
        firstAndsecondWord().1
    }
    
    func firstAndsecondWord() -> (String?, String?) {
        let words = split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        let first = words.first.map(String.init)
        let second = words.dropFirst().first.map(String.init)
        return (first, second)
    }
    
    func lastWord() -> String? {
        var end = endIndex

        while end > startIndex {
            let previous = index(before: end)
            if !self[previous].isWhitespace {
                break
            }
            end = previous
        }

        guard end > startIndex else { return nil }

        var start = end
        while start > startIndex {
            let previous = index(before: start)
            if self[previous].isWhitespace {
                break
            }
            start = previous
        }

        return String(self[start..<end])
    }
    
    func dropFirstWord() -> String {
        if let firstWord = firstWord() {
            return remainingLine(after: firstWord)
        } else {
            return self
        }
    }
    
    func dropLastWord() -> String {
        var end = endIndex

        while end > startIndex {
            let previous = index(before: end)
            if !self[previous].isWhitespace {
                break
            }
            end = previous
        }

        guard end > startIndex else { return "" }

        var lastWordStart = end
        while lastWordStart > startIndex {
            let previous = index(before: lastWordStart)
            if self[previous].isWhitespace {
                break
            }
            lastWordStart = previous
        }

        let prefix = self[..<lastWordStart]
        var result = ""
        var index = prefix.startIndex
        var needsSpace = false

        while index < prefix.endIndex {
            while index < prefix.endIndex, prefix[index].isWhitespace {
                prefix.formIndex(after: &index)
            }
            guard index < prefix.endIndex else { break }

            let wordStart = index
            while index < prefix.endIndex, !prefix[index].isWhitespace {
                prefix.formIndex(after: &index)
            }

            if needsSpace {
                result += " "
            }
            result += String(prefix[wordStart..<index])
            needsSpace = true
        }

        return result
    }
    
    func dropFirstAndLastWords() -> String {
        let firstWordDropped = dropFirstWord()
        return firstWordDropped.dropLastWord()
    }
    
    func trim() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func trimTrailing() -> String {
        guard let index = lastIndex(where: { !$0.isWhitespace && !$0.isNewline }) else {
            return self
        }

        return String(self[...index])
    }
    
    func stmtPartOnly() -> String {
        return remainingLine(after: TemplateConstants.stmtKeyWord).trim()
    }
    
    func lineWithoutStmtKeyword() -> String {
        return remainingLine(after: TemplateConstants.stmtKeyWord)
    }
    
    func remainingLine(after word: String) -> String {
        let currentLine = self
        
        if let range = currentLine.range(of: word) {
            let remainingLine =  String(currentLine[range.upperBound...])
            return remainingLine.trim()
        } else {
            return currentLine.trim()
        }
    }
    
    func between(prefix: String, suffix: String) -> String? {
        guard let prefixRange = self.range(of: prefix) else { return nil }
        
        let startIndex = prefixRange.upperBound
        guard let suffixRange = self[startIndex...].range(of: suffix) else { return nil }
        
        let endIndex = suffixRange.lowerBound
        return String(self[startIndex..<endIndex])
    }
    
    var isStartingWithAlphabet : Bool {
        return first?.isAsciiLetter == true
    }
    
    func slugify() -> String {
        return self.lowercased().normalizeForFolderName().camelCaseToSnakeCase()
    }
    
    func normalizeForVariableName() -> String {
        var code  = self
        //code = code.replacingOccurrences(of: "-", with: "")
        code = code.replacingOccurrences(of: " ", with: "")
        code = code.replacingMatches(using: StringRegexCache.normalizeForVariableName, withTemplate: "_")

        if  let first = code.first, first.isNumber {
            code = "value" + code
        }
        
//        //make all lower case to upper case names, so as not to clash with js keywords which are all lowercase
//        if  let first = code.first, first.isLowercase {
//            let dropped = code.dropFirst()
//            code = first.uppercased() + String(dropped)
//        }
        
        return code
    }
    
    func normalizeForPackageName() -> String {
        var code  = self
        //code = code.replacingOccurrences(of: "-", with: "")
        code = code.replacingOccurrences(of: " ", with: ".")
        code = code.replacingMatches(using: StringRegexCache.normalizeForPackageName, withTemplate: "_")
        
        if  let first = code.first, first.isNumber {
            code = "value" + code
        }
        
        //        //make all lower case to upper case names, so as not to clash with js keywords which are all lowercase
        //        if  let first = code.first, first.isLowercase {
        //            let dropped = code.dropFirst()
        //            code = first.uppercased() + String(dropped)
        //        }
        
        return code
    }
    
    func normalizeForId() -> String {
        var code  = self
        code = code.replacingOccurrences(of: "-", with: "")
        code = code.replacingMatches(using: StringRegexCache.normalizeForId, withTemplate: "")
        
        return code
    }
    
    func normalizeForFolderName() -> String {
        var code  = self
        code = code.replacingMatches(using: StringRegexCache.normalizeForFolderName, withTemplate: "-")
        
        return code
    }
    
    func pluralized(count: Int = 2) -> String {
        guard (count > 1) else {
            return self
        }
    
        return PluralKit.shared.apply(word: self)
    }
    
    func hasDot() -> Bool {
        if let _ = self.firstIndex(of: ".") {
            return true
        } else {
            return false
        }
    }
    
    func uppercasedFirst() -> String {
        guard let first = self.first else { return self }
        return String(first).uppercased() + self[self.index(self.startIndex, offsetBy: 1)...]
    }
    func withoutFileExtension() -> String {
        let url = URL(string: self)
        let filename = url?.deletingPathExtension().lastPathComponent
        return filename ?? self
    }
    
    func fileExtension() -> String {
        let url = URL(string: self)
        let ext = url?.pathExtension
        return ext ?? self
    }
    
    //removes all spaces in the string
    //for selective spaces, replace 🔥 symbol with a single space
    func spaceless() -> String {
        let withoutSpace = String(self.filter { !$0.isWhitespace && !$0.isNewline })
        return withoutSpace.replacingOccurrences(of: "🔥", with: " ")
    }
    
    static let newLine = "\n"
    
    static let newLine2 = "\r\n"

    func splitIntoLines() -> [String] {
        splitIntoLineSubstrings().map(String.init)
    }

    func splitIntoLineSubstrings() -> [Substring] {
        split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    /// Splits on `separator`, trims each token, and drops empty results.
    func splitTrimmed(separator: Character) -> [String] {
        split(separator: separator).compactMap {
            let t = $0.trim()
            return t.isEmpty ? nil : String(t)
        }
    }
}

public extension Array where Element == String {
    func trim() -> [String] {
        var arr : [String] = []
        for str in self {
            arr.append(str.trim())
        }
        return arr
    }
}

public extension Substring {
    var isNotEmpty: Bool { !isEmpty }
    var nonEmpty: Substring? { isEmpty ? nil : self }

    /// First whitespace-delimited token; slice of `self` (no allocation beyond the view).
    func firstWord() -> Substring? {
        var i = startIndex
        while i < endIndex, self[i].isWhitespace {
            formIndex(after: &i)
        }
        guard i < endIndex else { return nil }
        let wordStart = i
        while i < endIndex, !self[i].isWhitespace {
            formIndex(after: &i)
        }
        return self[wordStart..<i]
    }

    func trimTrailing() -> Substring {
        guard let index = lastIndex(where: { !$0.isWhitespace && !$0.isNewline }) else {
            return self[startIndex..<startIndex]
        }
        return self[...index]
    }

    /// Leading/trailing trim without allocating a new `String` (slice of `self`).
    func trim() -> Substring {
        guard let start = firstIndex(where: { !$0.isWhitespace && !$0.isNewline }) else {
            return self[startIndex..<startIndex]
        }
        let end = lastIndex(where: { !$0.isWhitespace && !$0.isNewline })!
        return self[start...end]
    }
    // MARK: - Delegation to `String` helpers (trimmed lines from `LineParser` are often `Substring`)
    func hasOnly(_ txt: String) -> Bool { String(self).hasOnly(txt) }
    func hasOnly(_ times: Int, of txt: String) -> Bool { String(self).hasOnly(times, of: txt) }
    func has(prefix: String, filler txt: String, suffix: String) -> Bool {
        String(self).has(prefix: prefix, filler: txt, suffix: suffix)
    }
    /// Last whitespace-delimited token (see `String.lastWord()`).
    func lastWord() -> String? { String(self).lastWord() }
    func dropFirstAndLastWords() -> String { String(self).dropFirstAndLastWords() }
    var isStartingWithAlphabet: Bool { String(self).isStartingWithAlphabet }

}

public extension Array where Element == Substring {
    func trim() -> [String] {
        var arr: [String] = []
        for str in self {
            arr.append(String(str.trim()))
        }
        return arr
    }
}

//SRC: https://gist.github.com/dmsl1805/ad9a14b127d0409cf9621dc13d237457
public extension String {
  func camelCaseToSnakeCase() -> String {
    replacingMatches(using: StringRegexCache.camelAcronym, withTemplate: "$1_$2")
      .replacingMatches(using: StringRegexCache.camelFullWords, withTemplate: "$1_$2")
      .replacingMatches(using: StringRegexCache.camelDigitsFirst, withTemplate: "$1_$2")
      .lowercased()
  }

    func camelCaseToKebabCase() -> String {
      replacingMatches(using: StringRegexCache.camelAcronym, withTemplate: "$1-$2")
        .replacingMatches(using: StringRegexCache.camelFullWords, withTemplate: "$1-$2")
        .replacingMatches(using: StringRegexCache.camelDigitsFirst, withTemplate: "$1-$2")
        .lowercased()
    }
}

private extension String {
    func replacingMatches(using regex: NSRegularExpression, withTemplate template: String) -> String {
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: template)
    }
}

extension Character {
    var isAsciiLetter: Bool { "A"..."Z" ~= self || "a"..."z" ~= self }
}
