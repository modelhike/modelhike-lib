//
//  Template.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public protocol Template: StringConvertible, Sendable {
    var name: String {get}
}

public protocol PlaceHolderTemplate: Template { }

public protocol ScriptedTemplate: Template { }

public protocol ProgrammedTemplate: Template { }

public enum TemplateStmtKind: Sendable {
    case block, line, blockOrLine, multiBlock
}

public protocol TemplateItem: Sendable {
    func execute(with ctx: Context) async throws -> String?
}

public protocol TemplateItemWithParsedInfo: TemplateItem {
    var pInfo: ParsedInfo {get}
}

public protocol TemplateItemConfig: Sendable {
    associatedtype T
    
    var keyword : String {get}
    var kind: TemplateStmtKind {get}
    func getNewObject(_ pInfo: ParsedInfo) -> T
}

public protocol TemplateInitialiserWithArg: Sendable {
    associatedtype T
    
    var initialiser: @Sendable (String, ParsedInfo) -> T {get}
}

public protocol TemplateInitialiserWithNoArg: Sendable {
    associatedtype T
    
    var initialiser: @Sendable (ParsedInfo) -> T {get}
}

struct TemplateExecutionSource: Sendable {
    let identifier: String
    let sourceContents: String
    let bodyContents: String
    let frontMatter: CachedTemplateFrontMatter?

    init(identifier: String, sourceContents: String, bodyContents: String, frontMatter: CachedTemplateFrontMatter?) {
        self.identifier = identifier
        self.sourceContents = sourceContents
        self.bodyContents = bodyContents
        self.frontMatter = frontMatter
    }

    static func parse(contents: String, identifier: String, parseFrontMatter: Bool) -> TemplateExecutionSource {
        if parseFrontMatter {
            let split = CachedTemplateFrontMatter.split(contents: contents, identifier: identifier)
            return TemplateExecutionSource(
                identifier: identifier,
                sourceContents: contents,
                bodyContents: split.body,
                frontMatter: split.frontMatter
            )
        }

        return TemplateExecutionSource(
            identifier: identifier,
            sourceContents: contents,
            bodyContents: contents,
            frontMatter: nil
        )
    }
}
