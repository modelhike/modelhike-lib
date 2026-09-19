//
//  UIViewElementsWrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor UIViewBinding_Wrap: DynamicMemberLookup, SendableDebugStringConvertible {
    private let data: UIViewBinding

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = UIViewBindingProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: UIViewBindingProperty.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return switch key {
        case .name: data.name
        case .typeName: data.typeName ?? ""
        case .isRequired: data.required == .yes
        }
    }

    public var debugDescription: String { get async { "\(data.name): \(data.typeName ?? "")" } }

    public init(_ data: UIViewBinding) {
        self.data = data
    }
}

private enum UIViewBindingProperty: String, CaseIterable {
    case name
    case typeName = "type-name"
    case isRequired = "is-required"
}

public actor UIViewSection_Wrap: DynamicMemberLookup, SendableDebugStringConvertible {
    private let data: UIViewSection

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = UIViewSectionProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: UIViewSectionProperty.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return switch key {
        case .name: data.name
        case .controls: data.controls.map { UIViewBinding_Wrap($0) }
        case .hasControls: data.controls.isNotEmpty
        }
    }

    public var debugDescription: String { get async { "\(data.name) (\(data.controls.count) controls)" } }

    public init(_ data: UIViewSection) {
        self.data = data
    }
}

private enum UIViewSectionProperty: String, CaseIterable {
    case name
    case controls
    case hasControls = "has-controls"
}

public actor UIActionHandler_Wrap: DynamicMemberLookup, SendableDebugStringConvertible {
    private let data: UIActionHandler

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = UIActionHandlerProperty(rawValue: propname) else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: UIActionHandlerProperty.allCases.map(\.rawValue),
                pInfo: pInfo
            )
        }
        return switch key {
        case .trigger: data.trigger
        case .lines: await data.lines.map(\.text)
        case .hasLines: data.lines.isNotEmpty
        }
    }

    public var debugDescription: String { get async { "\(data.trigger) (\(data.lines.count) lines)" } }

    public init(_ data: UIActionHandler) {
        self.data = data
    }
}

private enum UIActionHandlerProperty: String, CaseIterable {
    case trigger
    case lines
    case hasLines = "has-lines"
}
