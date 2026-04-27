//
//  PrintableObject.swift
//  ModelHike
//

import Foundation

public struct PrintableTableColumn: Sendable {
    public let title: String
    public let binding: String
    public let pInfo: ParsedInfo
}

public struct PrintableTable: Sendable {
    public let source: String
    public var columns: [PrintableTableColumn]
    public let pInfo: ParsedInfo
}

public struct PrintableSection: Sendable {
    public let name: String
    public let layout: String?
    public var rows: [DSLBodyLine]
    public var tables: [PrintableTable]
    public let pInfo: ParsedInfo
}

public struct PrintableConditional: Sendable {
    public let condition: String
    public let pInfo: ParsedInfo
}

public struct PrintablePageBreak: Sendable {
    public let rule: String
    public let pInfo: ParsedInfo
}

public actor PrintableObject: ArtifactHolderWithAttachedSections, HasTechnicalImplications_Actor, HasDescription_Actor {
    let sourceLocation: SourceLocation

    public let attribs = Attributes()
    public let tags = Tags()
    public let technicalImplications = TechnicalImplications()
    public let annotations = Annotations()
    public var attachedSections = AttachedSections()
    public var attached: [Artifact] = []

    public let givenname: String
    public let name: String
    public let dataType: ArtifactKind = .printable
    public private(set) var description: String?

    public private(set) var directives: [DSLDirective] = []
    public private(set) var boundObjects: [String] = []
    public private(set) var outputFormats: [String] = []
    public private(set) var page: String?
    public private(set) var locale: String?
    public private(set) var headerRows: [DSLBodyLine] = []
    public private(set) var footerRows: [DSLBodyLine] = []
    public private(set) var sections: [PrintableSection] = []
    public private(set) var conditionals: [PrintableConditional] = []
    public private(set) var pageBreaks: [PrintablePageBreak] = []

    public func setDescription(_ value: String?) {
        description = value
    }

    @discardableResult
    public func appendAttached(_ item: Artifact) -> Self {
        attached.append(item)
        return self
    }

    public func setBoundObjects(_ values: [String]) {
        boundObjects = values
    }

    public func append(directive: DSLDirective) {
        directives.append(directive)
        switch directive.name.lowercased() {
        case "output": outputFormats = ExtendedDSLParserSupport.splitCommaList(directive.value)
        case "page": page = directive.value
        case "locale": locale = directive.value
        default: break
        }
    }

    public func appendHeaderRow(_ line: DSLBodyLine) {
        headerRows.append(line)
    }

    public func appendFooterRow(_ line: DSLBodyLine) {
        footerRows.append(line)
    }

    public func append(section: PrintableSection) {
        sections.append(section)
    }

    public func appendRowToLastSection(_ line: DSLBodyLine) {
        guard sections.isNotEmpty else { return }
        sections[sections.count - 1].rows.append(line)
    }

    public func appendTableToLastSection(_ table: PrintableTable) {
        guard sections.isNotEmpty else { return }
        sections[sections.count - 1].tables.append(table)
    }

    public func appendColumnToLastTable(_ column: PrintableTableColumn) {
        guard sections.isNotEmpty, sections[sections.count - 1].tables.isNotEmpty else { return }
        let sectionIndex = sections.count - 1
        let tableIndex = sections[sectionIndex].tables.count - 1
        sections[sectionIndex].tables[tableIndex].columns.append(column)
    }

    public func append(conditional: PrintableConditional) {
        conditionals.append(conditional)
    }

    public func append(pageBreak: PrintablePageBreak) {
        pageBreaks.append(pageBreak)
    }

    public var debugDescription: String {
        get async {
            "\(name) : printable sections=\(sections.count)"
        }
    }

    public init(name: String, sourceLocation: SourceLocation) {
        self.sourceLocation = sourceLocation
        self.givenname = name.trim()
        self.name = name.normalizeForVariableName()
    }
}
