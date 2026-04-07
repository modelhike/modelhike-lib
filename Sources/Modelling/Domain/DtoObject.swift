//
//  DtoObject.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor DtoObject : CodeObject {
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
    public private(set) var description: String?

    public func setDescription(_ value: String?) {
        self.description = value
    }

    private var _cachedDerivedProperties: [DerivedProperty]?
    private var _cachedProperties: [Property]?
    private var _cachedMethods: [MethodObject]?

    public var derivedProperties: [DerivedProperty] {
        get async {
            if let cached = _cachedDerivedProperties { return cached }
            let computed: [DerivedProperty] = ParserUtil.filterCodeMembers(members)
            _cachedDerivedProperties = computed
            return computed
        }
    }

    public var properties: [Property] {
        get async {
            if let cached = _cachedProperties { return cached }
            let derivedList = await derivedProperties
            let computed = await derivedList.compactMap { await $0.prop }
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
    
    public func populateDerivedProperties() async throws {
        let derivedList = await derivedProperties
        var i = 0

        while i < derivedList.count {
            let derivedProperty = derivedList[i]
            for mixin in mixins {
                let nameToCompare = await derivedProperty.name.lowercased()
                
                if await mixin.hasProp(nameToCompare) {
                    if let prop = await mixin.getProp(nameToCompare) {
                        await derivedProperty.prop(prop)
                    }
                }

            }
            
            if await derivedProperty.prop == nil { //no matching name found
                let msg = "\(await derivedProperty.givenname) in \(self.givenname)"
                throw Model_ParsingError.invalidDerivedProperty(msg, derivedProperty.pInfo)
            }
            
            i += 1
        }
    }
    
    @discardableResult
    public func append(_ item: CodeMember) -> Self {
        members.append(item)
        _cachedDerivedProperties = nil
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
