//
//  InlineModelLoader+Codable.swift
//  ModelHike
//

import Foundation

extension InlineModel: Codable {
    enum CodingKeys: String, CodingKey {
        case identifier
        case content
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(String.self, forKey: .identifier)
        let content = try container.decode(String.self, forKey: .content)
        self.identifier = identifier
        self.items = [content]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(string, forKey: .content)
    }
}

extension InlineCommonTypes: Codable {
    enum CodingKeys: String, CodingKey {
        case identifier
        case content
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(String.self, forKey: .identifier)
        let content = try container.decode(String.self, forKey: .content)
        self.identifier = identifier
        self.items = [content]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(string, forKey: .content)
    }
}

extension InlineConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case identifier
        case content
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(String.self, forKey: .identifier)
        let content = try container.decode(String.self, forKey: .content)
        self.identifier = identifier
        self.items = [content]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(string, forKey: .content)
    }
}

public struct InlineModelSnapshot: Codable, Sendable, Equatable {
    public let model: InlineModel
    public let commonTypes: InlineCommonTypes?
    public let config: InlineConfig?

    public init(model: InlineModel, commonTypes: InlineCommonTypes? = nil, config: InlineConfig? = nil) {
        self.model = model
        self.commonTypes = commonTypes
        self.config = config
    }

    public func toInlineModel() -> InlineModel {
        model
    }

    public func toCommonTypes() -> InlineCommonTypes? {
        commonTypes
    }

    public func toConfig() -> InlineConfig? {
        config
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

    public static func fromJSON(_ json: String) throws -> InlineModelSnapshot {
        try fromJSON(Data(json.utf8))
    }

    public static func fromJSON(_ data: Data) throws -> InlineModelSnapshot {
        try JSONDecoder().decode(Self.self, from: data)
    }

    public static func == (lhs: InlineModelSnapshot, rhs: InlineModelSnapshot) -> Bool {
        lhs.model.identifier == rhs.model.identifier &&
        lhs.model.string == rhs.model.string &&
        lhs.commonTypes?.identifier == rhs.commonTypes?.identifier &&
        lhs.commonTypes?.string == rhs.commonTypes?.string &&
        lhs.config?.identifier == rhs.config?.identifier &&
        lhs.config?.string == rhs.config?.string
    }
}

public extension InlineModel {
    func toSnapshot(commonTypes: InlineCommonTypes? = nil, config: InlineConfig? = nil) -> InlineModelSnapshot {
        InlineModelSnapshot(model: self, commonTypes: commonTypes, config: config)
    }

    func toJSON(prettyPrinted: Bool = true) throws -> String {
        try InlineModelSnapshot(model: self).toJSON(prettyPrinted: prettyPrinted)
    }
}
