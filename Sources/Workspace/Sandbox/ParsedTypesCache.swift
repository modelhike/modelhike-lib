//
//  ParsedTypesCache.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor ParsedTypesCache : SendableDebugStringConvertible {
    public private(set) var items: [CodeObject] = []
    private var nameIndex: [String: CodeObject] = [:]
    private var givennameIndex: [String: CodeObject] = [:]

    public func getLastPropInRecursive(_ propName: String, inObj objectName: String) async -> Property? {
        if let obj = await self.get(for: objectName) {
            if let prop = await obj.getLastPropInRecursive(propName, appModel: self) {
                return prop
            }
        }
        
        return nil
    }
        
    public func get(for name: String) async -> CodeObject? {
        let normalizedName = name.lowercased()
        if let found = nameIndex[normalizedName] { return found }
        if let found = givennameIndex[normalizedName] { return found }

        for fallback in normalizedFallbackNames(for: name) {
            if let found = nameIndex[fallback] { return found }
            if let found = givennameIndex[fallback] { return found }
        }
        return nil
    }


    private func normalizedFallbackNames(for name: String) -> [String] {
        var normalized: [String] = []
        for candidate in referenceFallbackNames(for: name) {
            normalized.append(candidate.lowercased())
        }
        return normalized
    }

    private func referenceFallbackNames(for name: String) -> [String] {
        if let targets = PropertyKind.parse(name).referenceTargets {
            targets.map(\.targetName).filter(\.isNotEmpty)
        } else {
            []
        }
    }

     
    public func append(_ item: CodeObject) async {
        items.append(item)
        nameIndex[await item.name.lowercased()] = item
        givennameIndex[await item.givenname.lowercased()] = item
    }

    public func append(_ newItems: [CodeObject]) async {
        for item in newItems {
            await append(item)
        }
    }
    
    public var debugDescription: String { get async {
        var str =  """
                    Types \(self.items.count) items:
                    """
        str += .newLine
        
        for item in items {
            let givenname = await item.givenname
            str += givenname + .newLine
            
        }
        
        return str
    }}
    
    public init() {}
}
