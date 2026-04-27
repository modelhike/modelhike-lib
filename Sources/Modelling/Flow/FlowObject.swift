//
//  FlowObject.swift
//  ModelHike
//

import Foundation

public enum FlowMode: String, Sendable {
    case lifecycle
    case workflow
    case unified
}

public enum FlowMessageArrow: String, Sendable {
    case sync = "-->"
    case async = "~~>"
    case response = "<--"
}

public struct FlowAction: Sendable {
    public let text: String
    public let depth: Int
    public let pInfo: ParsedInfo
}

public struct FlowState: Sendable {
    public let name: String
    public var actions: [FlowAction]
    public var isTerminal: Bool
    public let pInfo: ParsedInfo
}

public struct FlowTransition: Sendable {
    public let from: String
    public let to: String
    public let event: String?
    public let guardExpression: String?
    public let roles: [String]
    public var actions: [FlowAction]
    public let pInfo: ParsedInfo
}

public struct FlowParticipant: Sendable {
    public let name: String
    public let kind: String
    public let pInfo: ParsedInfo
}

public struct FlowMessage: Sendable {
    public let from: String
    public let to: String
    public let arrow: FlowMessageArrow
    public let call: String
    public let pInfo: ParsedInfo
}

public struct FlowWait: Sendable {
    public let participant: String
    public let task: String
    public let result: String?
    public var directives: [DSLBodyLine]
    public let pInfo: ParsedInfo
}

public struct FlowCall: Sendable {
    public let kind: String
    public let target: String
    public let arguments: String?
    public let result: String?
    public let pInfo: ParsedInfo
}

public struct FlowStep: Sendable {
    public let title: String
    public let pInfo: ParsedInfo
}

public struct FlowParallelRegion: Sendable {
    public let name: String?
    public var actions: [FlowAction]
    public let pInfo: ParsedInfo
}

public struct FlowBranch: Sendable {
    public let keyword: String
    public let condition: String?
    public let depth: Int
    public let pInfo: ParsedInfo
}

public actor FlowObject: ArtifactHolderWithAttachedSections, HasTechnicalImplications_Actor, HasDescription_Actor {
    let sourceLocation: SourceLocation

    public let attribs = Attributes()
    public let tags = Tags()
    public let technicalImplications = TechnicalImplications()
    public let annotations = Annotations()
    public var attachedSections = AttachedSections()
    public var attached: [Artifact] = []

    public let givenname: String
    public let name: String
    public private(set) var dataType: ArtifactKind = .flow
    public private(set) var description: String?

    public private(set) var directives: [DSLDirective] = []
    public private(set) var states: [FlowState] = []
    public private(set) var transitions: [FlowTransition] = []
    public private(set) var participants: [FlowParticipant] = []
    public private(set) var messages: [FlowMessage] = []
    public private(set) var waits: [FlowWait] = []
    public private(set) var calls: [FlowCall] = []
    public private(set) var steps: [FlowStep] = []
    public private(set) var parallelRegions: [FlowParallelRegion] = []
    public private(set) var branches: [FlowBranch] = []
    public private(set) var returns: [DSLBodyLine] = []

    public var mode: FlowMode {
        switch dataType {
        case .lifecycle: .lifecycle
        case .workflow: .workflow
        default: .unified
        }
    }

    public func setDescription(_ value: String?) {
        description = value
    }

    @discardableResult
    public func appendAttached(_ item: Artifact) -> Self {
        attached.append(item)
        return self
    }

    public func append(directive: DSLDirective) {
        directives.append(directive)
    }

    public func append(state: FlowState) {
        states.append(state)
    }

    public func append(transition: FlowTransition) {
        transitions.append(transition)
    }

    public func append(participant: FlowParticipant) {
        participants.append(participant)
    }

    public func append(message: FlowMessage) {
        messages.append(message)
    }

    public func append(wait: FlowWait) {
        waits.append(wait)
    }

    public func append(call: FlowCall) {
        calls.append(call)
    }

    public func append(step: FlowStep) {
        steps.append(step)
    }

    public func append(parallelRegion: FlowParallelRegion) {
        parallelRegions.append(parallelRegion)
    }

    public func append(branch: FlowBranch) {
        branches.append(branch)
    }

    public func append(returnLine: DSLBodyLine) {
        returns.append(returnLine)
    }

    public func appendActionToLastState(_ action: FlowAction) {
        guard states.isNotEmpty else { return }
        states[states.count - 1].actions.append(action)
        if action.text == "terminal" {
            states[states.count - 1].isTerminal = true
        }
    }

    public func appendActionToLastTransition(_ action: FlowAction) {
        guard transitions.isNotEmpty else { return }
        transitions[transitions.count - 1].actions.append(action)
    }

    public func appendDirectiveToLastWait(_ line: DSLBodyLine) {
        guard waits.isNotEmpty else { return }
        waits[waits.count - 1].directives.append(line)
    }

    public func appendActionToLastParallelRegion(_ action: FlowAction) {
        guard parallelRegions.isNotEmpty else { return }
        parallelRegions[parallelRegions.count - 1].actions.append(action)
    }

    public func finalizeMode() {
        let hasStates = states.isNotEmpty
        let hasWorkflowSignals = participants.isNotEmpty || messages.isNotEmpty || waits.isNotEmpty
        if hasStates && hasWorkflowSignals {
            dataType = .flow
        } else if hasStates {
            dataType = .lifecycle
        } else {
            dataType = .workflow
        }
    }

    public var debugDescription: String {
        get async {
            "\(name) : \(String(describing: dataType)) states=\(states.count) transitions=\(transitions.count) participants=\(participants.count)"
        }
    }

    public init(name: String, sourceLocation: SourceLocation) {
        self.sourceLocation = sourceLocation
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
    }
}
