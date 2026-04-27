//
//  PrintableObjectWrap.swift
//  ModelHike
//

import Foundation

public actor PrintableObject_Wrap: ObjectWrapper {
    public let item: PrintableObject
    public var attribs: Attributes { get async { await item.attribs } }

    public func getValueOf(property propname: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        guard let key = PrintableObjectProperty(rawValue: propname) else {
            return try await resolveFallbackProperty(propname: propname, pInfo: pInfo)
        }
        return switch key {
        case .name: await item.name
        case .givenName: await item.givenname
        case .description: await item.description ?? ""
        case .hasDescription: (await item.description).map { $0.isNotEmpty } ?? false
        case .boundObjects: await item.boundObjects
        case .outputFormats: await item.outputFormats
        case .page: await item.page ?? ""
        case .locale: await item.locale ?? ""
        case .headerRows: await item.headerRows
        case .footerRows: await item.footerRows
        case .sections: await item.sections
        case .conditionals: await item.conditionals
        case .pageBreaks: await item.pageBreaks
        }
    }

    private func resolveFallbackProperty(propname: String, pInfo: ParsedInfo) async throws -> Sendable {
        if await item.attribs.has(propname) {
            return await item.attribs[propname]
        }
        throw Suggestions.invalidPropertyInCall(propname, candidates: PrintableObjectProperty.allCases.map(\.rawValue), pInfo: pInfo)
    }

    public var debugDescription: String { get async { await item.debugDescription } }

    public init(_ item: PrintableObject) {
        self.item = item
    }
}

private enum PrintableObjectProperty: String, CaseIterable {
    case name
    case givenName = "given-name"
    case description
    case hasDescription = "has-description"
    case boundObjects = "bound-objects"
    case outputFormats = "output-formats"
    case page
    case locale
    case headerRows = "header-rows"
    case footerRows = "footer-rows"
    case sections
    case conditionals
    case pageBreaks = "page-breaks"
}
