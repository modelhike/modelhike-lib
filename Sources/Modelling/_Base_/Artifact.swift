//
//  Artifact.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public protocol Artifact_NonActor: HasAttributes, HasAnnotations, HasTags,
    CustomDebugStringConvertible, Sendable
{
    var givenname: String { get }
    var name: String { get }
    var dataType: ArtifactKind { get }
}

public protocol Artifact: HasAttributes_Actor, HasAnnotations_Actor, HasTags_Actor,
    SendableDebugStringConvertible, Actor
{
    var givenname: String { get }
    var name: String { get }
    var dataType: ArtifactKind { get }
}

public protocol ArtifactHolder: Artifact {

}

public protocol ArtifactHolder_NonActor: Artifact_NonActor {

}

public protocol ArtifactHolderWithAttachedSections: ArtifactHolder, HasAttachedSections {

}

typealias ArtifactHolderBuilder = ResultBuilder<ArtifactHolder>

public enum ArtifactKind: Sendable {
    case unKnown, container, entity, service, dataAccessLayer, 
    embeddedType, valueType, dto, 
    api, apiInput_forGraphQL, 
    cache, 
    workflow, lifecycle, flow, hierarchy,
    rules, printable, configObject, 
    event, agent, data, ui, uxFlow,  
    attachedSection, custom
}
