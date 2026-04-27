//
//  AgentObject.swift
//  ModelHike
//

import Foundation

public enum AgentComponentKind: String, Sendable {
    case agent
    case subAgent = "sub-agent"
}

public enum AgentResourceKind: String, Sendable {
    case tool
    case skill
    case mcpServer = "mcp-server"
}

public struct AgentPrompt: Sendable {
    public let kind: String
    public let condition: String?
    public let body: [String]
    public let pInfo: ParsedInfo
}

public struct AgentDelegation: Sendable {
    public let keyword: String
    public let target: String?
    public let arguments: String?
    public let result: String?
    public let raw: String
    public let pInfo: ParsedInfo
}

public struct AgentTool: Sendable {
    public let name: String
    public let resourceKind: AgentResourceKind
    public var descriptionLines: [String]
    public var method: MethodObject?
    public var directives: [DSLDirective]
    public var prompts: [AgentPrompt]
    public var delegations: [AgentDelegation]
    public let pInfo: ParsedInfo
}

public struct AgentSection: Sendable {
    public let name: String
    public var lines: [DSLBodyLine]
    public let pInfo: ParsedInfo
}

public actor AgentObject: ArtifactHolderWithAttachedSections, HasTechnicalImplications_Actor, HasDescription_Actor {
    public let attribs = Attributes()
    public let tags = Tags()
    public let technicalImplications = TechnicalImplications()
    public let annotations = Annotations()
    public var attachedSections = AttachedSections()
    public var attached: [Artifact] = []

    public let givenname: String
    public let name: String
    public let dataType: ArtifactKind = .agent
    public let componentKind: AgentComponentKind
    public private(set) var description: String?
    public private(set) var prompts: [AgentPrompt] = []
    public private(set) var tools: [AgentTool] = []
    public private(set) var sections: [AgentSection] = []

    public var guardrails: [AgentSection] {
        sections.filter { $0.name.lowercased() == "guardrails" }
    }

    public var slashCommands: [AgentSection] {
        sections.filter { $0.name.lowercased() == "slash commands" }
    }

    public init(name: String, componentKind: AgentComponentKind) {
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
        self.componentKind = componentKind
    }

    public func setDescription(_ value: String?) {
        description = value
    }

    @discardableResult
    public func appendAttached(_ item: Artifact) -> Self {
        attached.append(item)
        return self
    }

    public func append(prompt: AgentPrompt) {
        prompts.append(prompt)
    }

    public func append(tool: AgentTool) {
        tools.append(tool)
    }

    public func append(section: AgentSection) {
        sections.append(section)
    }

    public var debugDescription: String {
        get async {
            "\(name) : \(componentKind.rawValue) prompts=\(prompts.count) tools=\(tools.count)"
        }
    }
}
