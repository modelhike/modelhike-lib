//
//  UIObject_Wrap.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor UIObject_Wrap: ObjectWrapper {
    public let item: UIObject

    public var attribs: Attributes { get async { await item.attribs }}

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = UIObjectProperty(rawValue: propname) else {
            //nothing found; so check in module attributes
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        let value: Sendable = switch key {
        case .name: await item.name
        case .givenName: await item.givenname
        case .description: await uiDescription()
        case .hasDescription: await uiHasDescription()
        case .title: await uiTitle()
        case .sections: await uiSections()
        case .hasSections: await uiSections().isNotEmpty
        case .bindings: await uiBindings()
        case .hasBindings: await uiBindings().isNotEmpty
        case .actions: await uiActions()
        case .hasActions: await uiActions().isNotEmpty
        }
        return value
    }

    private func uiDescription() async -> String {
        if let v = item as? UIView { return await v.description ?? "" }
        return ""
    }

    private func uiHasDescription() async -> Bool {
        if let v = item as? UIView {
            let d = await v.description
            return d.map { $0.isNotEmpty } ?? false
        }
        return false
    }

    private func uiTitle() async -> String {
        guard let v = item as? UIView else { return "" }
        return await v.directives.first(where: { $0.name == "title" })?.value ?? ""
    }

    private func uiSections() async -> [UIViewSection_Wrap] {
        guard let v = item as? UIView else { return [] }
        return await v.sections.map { UIViewSection_Wrap($0) }
    }

    private func uiBindings() async -> [UIViewBinding_Wrap] {
        guard let v = item as? UIView else { return [] }
        return await v.bindings.map { UIViewBinding_Wrap($0) }
    }

    private func uiActions() async -> [UIActionHandler_Wrap] {
        guard let v = item as? UIView else { return [] }
        return await v.actions.map { UIActionHandler_Wrap($0) }
    }

    private func propertyCandidates() async -> [String] {
        let attributes = await item.attribs.attributesList
        let attributeNames = attributes.map { $0.givenKey }
        return UIObjectProperty.allCases.map(\.rawValue) + attributeNames
    }

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws -> Sendable {
        let attribs = await item.attribs
        if await attribs.has(propname) {
            return await attribs[propname]
        } else {
            throw Suggestions.invalidPropertyInCall(
                propname,
                candidates: await propertyCandidates(),
                pInfo: pInfo
            )
        }
    }
    
    public var debugDescription: String { get async { await item.debugDescription }}

    public init(_ item: UIObject) {
        self.item = item
    }
}

// MARK: - UI object property keys (template-facing raw strings)

private enum UIObjectProperty: String, CaseIterable {
    case name
    case givenName = "given-name"
    case description
    case hasDescription = "has-description"
    case title
    case sections
    case hasSections = "has-sections"
    case bindings
    case hasBindings = "has-bindings"
    case actions
    case hasActions = "has-actions"
}
