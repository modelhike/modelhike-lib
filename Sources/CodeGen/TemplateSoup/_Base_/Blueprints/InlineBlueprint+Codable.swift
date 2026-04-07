//
//  InlineBlueprint+Codable.swift
//  ModelHike
//

import Foundation

public struct InlineBlueprintSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let files: [String: [String: String]]

    enum CodingKeys: String, CodingKey {
        case name
        case files
        case scripts
        case templates
        case folders
        case modifiers
    }

    public init(name: String, files: [String: [String: String]]) {
        self.name = name
        self.files = files
    }

    public init(name: String, scripts: [String: String] = [:], templates: [String: String] = [:], folders: [String: [String: String]] = [:], modifiers: [String: String] = [:]) {
        var map: [String: [String: String]] = [:]
        for (scriptName, content) in scripts {
            map["", default: [:]]["\(scriptName).\(TemplateConstants.ScriptExtension)"] = content
        }
        for (templateName, content) in templates {
            map["", default: [:]]["\(templateName).\(TemplateConstants.TemplateExtension)"] = content
        }
        for (folderName, folderTemplates) in folders {
            for (templateName, content) in folderTemplates {
                map[folderName, default: [:]]["\(templateName).\(TemplateConstants.TemplateExtension)"] = content
            }
        }
        for (modifierName, content) in modifiers {
            map[SpecialFolderNames.modifiers, default: [:]]["\(modifierName).\(TemplateConstants.TemplateExtension)"] = content
        }
        self.init(name: name, files: map)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        if let files = try container.decodeIfPresent([String: [String: String]].self, forKey: .files) {
            self.init(name: name, files: files)
            return
        }
        self.init(
            name: name,
            scripts: try container.decodeIfPresent([String: String].self, forKey: .scripts) ?? [:],
            templates: try container.decodeIfPresent([String: String].self, forKey: .templates) ?? [:],
            folders: try container.decodeIfPresent([String: [String: String]].self, forKey: .folders) ?? [:],
            modifiers: try container.decodeIfPresent([String: String].self, forKey: .modifiers) ?? [:]
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(files, forKey: .files)
    }

    public func toInlineBlueprint() -> InlineBlueprint {
        InlineBlueprint(name: name, folderMap: files)
    }

    public func toJSON(prettyPrinted: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    public static func fromJSON(_ json: String) throws -> InlineBlueprintSnapshot {
        try fromJSON(Data(json.utf8))
    }

    public static func fromJSON(_ data: Data) throws -> InlineBlueprintSnapshot {
        try JSONDecoder().decode(Self.self, from: data)
    }
}
