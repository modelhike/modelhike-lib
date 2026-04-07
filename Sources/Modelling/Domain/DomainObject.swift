//
//  DomainObject.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor DomainObject : CodeObject {
    let sourceLocation: SourceLocation
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

    private var _cachedProperties: [Property]?
    private var _cachedMethods: [MethodObject]?

    public var properties: [Property] {
        get async {
            if let cached = _cachedProperties { return cached }
            let computed: [Property] = ParserUtil.filterCodeMembers(members)
            _cachedProperties = computed
            return computed
        }
    }

    public var methods: [MethodObject] {
        if let cached = _cachedMethods { return cached }
        let computed: [MethodObject] = ParserUtil.filterCodeMembers(members)
        _cachedMethods = computed
        return computed
    }
    
    public private(set) var dataType: ArtifactKind = .unKnown

    public func dataType(_ value: ArtifactKind) {
        self.dataType = value
    }
    
    @discardableResult
    func append(_ item: CodeMember) -> Self {
        members.append(item)
        _cachedProperties = nil
        _cachedMethods = nil
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
        self.sourceLocation = SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
        self.members = builder()
    }

    init(name: String, sourceLocation: SourceLocation) {
        self.sourceLocation = sourceLocation
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
    }
    
}
