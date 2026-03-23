//
//  ParserUtil.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public class ParserUtil {
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

