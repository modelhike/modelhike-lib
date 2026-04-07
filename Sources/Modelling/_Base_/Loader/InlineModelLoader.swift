//
//  InlineModelLoader.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

private enum InlineModelDefaults {
    static let domainIdentifier = "InlineDomain"
    static let commonIdentifier = "InlineCommons"
    static let configIdentifier = "config"
}

public struct InlineModelLoader : ModelRepository, Sendable {
    let ctx: LoadContext
    public let items: [any InlineModelProtocol]
    
    public func loadModel(to model: AppModel) async throws {
        for item in items {
            if let commonsItem = item as? InlineCommonTypes {
                let commons = try await ModelFileParser(with: ctx)
                                .parse(string: commonsItem.string, identifier: commonsItem.identifier)
                
                await model.appendToCommonModel(contentsOf: commons)
            }
        }
        
        //parse rest of the models
        for item in items {
            if let modelItem = item as? InlineModel {
                let modelSpace = try await ModelFileParser(with: ctx)
                    .parse(string: modelItem.string, identifier: modelItem.identifier)
                
                await model.append(contentsOf: modelSpace)
            }
        }
        
        try await model.resolveAndLinkItems(with: ctx)
    }
    
    public func probeForModelFiles() -> Bool {
        for item in items {
            if let _ = item as? InlineModel {
                return true
            }
        }
        
        return false
    }
    
    public func probeForCommonModelFiles() -> Bool {
        for item in items {
            if let _ = item as? InlineCommonTypes {
                return true
            }
        }
        
        return false
    }
    
    public func probeForGenerationConfig() -> Bool {
        for item in items {
            if let _ = item as? InlineConfig {
                return true
            }
        }
        
        return false
    }
    
    public func loadGenerationConfigIfAny() async throws {
        for item in items {
            if let modelConfig = item as? InlineConfig {
                try await ConfigFileParser(with: ctx)
                    .parse(string: modelConfig.string, identifier: modelConfig.identifier)
                
            }
        }
    }
    
    public init(with ctx: LoadContext, @InlineModelBuilder _ builder: () -> [any InlineModelProtocol]) {
        self.ctx = ctx
        self.items = builder()
    }
}

public struct InlineModel : InlineModelProtocol {
    public let identifier: String
    public var items: [StringConvertible] = []

    public init(@StringConvertibleBuilder _ builder : () -> [StringConvertible]) {
        self.init(identifier: InlineModelDefaults.domainIdentifier, builder)
    }

    public init(identifier: String, @StringConvertibleBuilder _ builder : () -> [StringConvertible]) {
        self.identifier = identifier
        items = builder()
    }
}

public struct InlineCommonTypes : InlineModelProtocol {
    public let identifier: String
    public var items: [StringConvertible] = []

    public init(@StringConvertibleBuilder _ builder : () -> [StringConvertible]) {
        self.init(identifier: InlineModelDefaults.commonIdentifier, builder)
    }

    public init(identifier: String, @StringConvertibleBuilder _ builder : () -> [StringConvertible]) {
        self.identifier = identifier
        items = builder()
    }
}
    
public struct InlineConfig : InlineModelProtocol {
    public let identifier: String
    public var items: [StringConvertible] = []
    
    public init(@StringConvertibleBuilder _ builder : () -> [StringConvertible]) {
        self.init(identifier: InlineModelDefaults.configIdentifier, builder)
    }

    public init(identifier: String, @StringConvertibleBuilder _ builder : () -> [StringConvertible]) {
        self.identifier = identifier
        items = builder()
    }
}

public protocol InlineModelProtocol: Sendable {
    var items: [StringConvertible] { get set}
    var string: String {get}
}

public extension InlineModelProtocol {
    var string: String {
        items.map { $0.toString() }.joined()
    }
}

typealias InlineModelBuilder = ResultBuilder<InlineModelProtocol>
