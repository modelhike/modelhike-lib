//
//  DomainObject.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor DomainObject : CodeObject {
    public var givenname: String
    public var name: String
    public var members : [CodeMember] = []
    public var attachedSections = AttachedSections()
    public var attached : [Artifact] = []
    public var mixins : [CodeObject] = []
    
    public var attribs = Attributes()
    public var tags = Tags()
    public var annotations = Annotations()
    /// Documentation from `--` or bare `>>>` blocks before the class.
    public private(set) var description: String?
    /// Reusable named constraints at class scope (`= name : { ... }`).
    public let namedConstraints = Constraints()

    public func setDescription(_ value: String?) {
        self.description = value
    }

    public var properties : [Property]  { get async { await members.compactMap({
        if let prop = $0 as? Property { return prop } else {return nil}
    }) }}
    
    public var methods : [MethodObject] { members.compactMap({
        if let method = $0 as? MethodObject { return method } else {return nil}
    }) }
    
    public private(set) var dataType: ArtifactKind = .unKnown

    public func dataType(_ value: ArtifactKind) {
        self.dataType = value
    }
    
    @discardableResult
    func append(_ item: CodeMember) -> Self {
        members.append(item)
        return self
    }
    
    public var debugDescription: String { get async {
        var str =  """
                    \(self.name) :
                    | Properties \(await self.properties.count) items:
                    """
        str += .newLine
        
        for property in await properties {
            await str += "| " + property.debugDescription + .newLine
            
        }
        
        return str
    }}
    
    public init(name: String, @CodeMemberBuilder _ builder: () -> [CodeMember]) {
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
        self.members = builder()
    }
    
    public init(name: String) {
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
    }
    
}
