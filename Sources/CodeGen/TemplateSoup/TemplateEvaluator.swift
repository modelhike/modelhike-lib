//
//  TemplateEvaluator.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

struct CompiledTemplate: Sendable {
    let source: TemplateExecutionSource
    let containers: SoupyScriptStmtContainerList
}

public struct TemplateEvaluator: TemplateSoupEvaluator {

    public func execute(template: Template, with context: GenerationContext) async throws -> String? {
        try await execute(template: template, with: context, consumeLeadingFrontMatter: true)
    }

    /// - Parameter consumeLeadingFrontMatter: When `false`, the template string is treated as body-only (e.g. blueprint already ran ``FrontMatter``). For internal use from ``TemplateSoup/renderTemplate(string:identifier:data:with:parseFrontMatter:)`` only.
    internal func execute(template: Template, with context: GenerationContext, consumeLeadingFrontMatter: Bool) async throws -> String? {
        let contents = template.toString()
        if let recorder = await context.debugRecorder {
            let file = SourceFile(identifier: template.name, fullPath: nil, content: contents, fileType: .template)
            await recorder.registerSourceFile(file)
        }
        let lineparser = LineParserDuringGeneration(
            string: contents, identifier: template.name, isStatementsPrefixedWithKeyword: true,
            with: context)

        return try await execute(lineParser: lineparser, with: context, consumeLeadingFrontMatter: consumeLeadingFrontMatter)
    }

    internal static func compile(templateSource: TemplateExecutionSource, with ctx: GenerationContext) async throws -> CompiledTemplate {
        let lineParser = LineParserDuringGeneration(
            string: templateSource.bodyContents,
            identifier: templateSource.identifier,
            isStatementsPrefixedWithKeyword: true,
            with: ctx
        )
        let parser = TemplateSoupParser(lineParser: lineParser, context: ctx)

        do {
            ctx.debugLog.templateParsingStarting(name: await lineParser.identifier)
            try await ctx.events.onBeforeParseTemplate?(lineParser.identifier, ctx)

            let containers = try await parser.parseContainers() ?? SoupyScriptStmtContainerList(name: templateSource.identifier)
            await ctx.debugLog.printParsedTree(for: containers)
            return CompiledTemplate(source: templateSource, containers: containers)
        } catch let err {
            try Self.rethrowAsTemplateError(err)
        }
    }

    internal static func execute(compiledTemplate: CompiledTemplate, with ctx: GenerationContext, frontMatterIdentifier: String? = nil) async throws -> String? {
        do {
            if let recorder = await ctx.debugRecorder {
                let file = SourceFile(
                    identifier: compiledTemplate.source.identifier,
                    fullPath: nil,
                    content: compiledTemplate.source.sourceContents,
                    fileType: .template
                )
                await recorder.registerSourceFile(file)
            }

            if let frontMatter = compiledTemplate.source.frontMatter {
                let runtimeFrontMatter = frontMatter.withIdentifier(frontMatterIdentifier)
                try await FrontMatter.processVariables(in: runtimeFrontMatter, with: ctx)
            }

            let pInfo = await ParsedInfo.dummy(
                line: "Compiled-Template",
                identifier: compiledTemplate.source.identifier,
                with: ctx
            )
            ctx.debugLog.templateExecutionStarting(name: compiledTemplate.source.identifier, pInfo: pInfo)
            try await ctx.events.onBeforeExecuteTemplate?(compiledTemplate.source.identifier, ctx)

            let body = try await compiledTemplate.containers.execute(with: ctx)
            ctx.debugLog.recordEvent(.templateCompleted(name: compiledTemplate.source.identifier))
            return body
        } catch let err {
            if let directive = err as? ParserDirective {
                if case let .throwErrorFromCurrentFile(filename, errMsg, pInfo) = directive {
                    ctx.debugLog.throwErrorFromCurrentFile(filename, err: errMsg, pInfo: pInfo)
                }
                return try Self.handleDirective(directive, with: ctx)
            } else {
                try Self.rethrowAsTemplateError(err)
            }
        }
    }

    public func execute(lineParser: LineParserDuringGeneration, with ctx: GenerationContext) async throws -> String? {
        try await execute(lineParser: lineParser, with: ctx, consumeLeadingFrontMatter: true)
    }

    internal func execute(lineParser: LineParserDuringGeneration, with ctx: GenerationContext, consumeLeadingFrontMatter: Bool) async throws -> String? {

        let parser = TemplateSoupParser(lineParser: lineParser, context: ctx)

        do {
            ctx.debugLog.templateParsingStarting(name: await lineParser.identifier)
            try await ctx.events.onBeforeParseTemplate?(lineParser.identifier, ctx)

            let curLine = await lineParser.currentLine()

            if consumeLeadingFrontMatter, curLine.hasOnly(TemplateConstants.frontMatterIndicator) {
                var frontMatter = try await FrontMatter(lineParser: lineParser, with: ctx)
                try await frontMatter.processVariables()
            }

            if let containers = try await parser.parseContainers() {
                await ctx.debugLog.printParsedTree(for: containers)

                let templateName = await lineParser.identifier
                let pInfo = await lineParser.currentParsedInfo(level: 0)
                ctx.debugLog.templateExecutionStarting(name: templateName, pInfo: pInfo)
                try await ctx.events.onBeforeExecuteTemplate?(lineParser.identifier, ctx)

                let body = try await containers.execute(with: ctx)
                ctx.debugLog.recordEvent(.templateCompleted(name: templateName))
                return body
            }
        } catch let err {
            if let directive = err as? ParserDirective {
                if case let .throwErrorFromCurrentFile(filename, errMsg, pInfo) = directive {
                    ctx.debugLog.throwErrorFromCurrentFile(filename, err: errMsg, pInfo: pInfo)
                }
                return try Self.handleDirective(directive, with: ctx)
            } else {
                try Self.rethrowAsTemplateError(err)
            }
        }

        return nil
    }

    private static func rethrowAsTemplateError(_ err: Error) throws -> Never {
        if let parseErr = err as? TemplateSoup_ParsingError {
            throw ParsingError.invalidLine(parseErr.pInfo, parseErr)
        } else if let evalErr = err as? TemplateSoup_EvaluationError {
            if case let .workingDirectoryNotSet(pInfo) = evalErr {
                throw EvaluationError.workingDirectoryNotSet(pInfo, evalErr)
            } else if case let .unIdentifiedStmt(pInfo) = evalErr {
                throw EvaluationError.invalidLine(pInfo, evalErr)
            } else {
                throw EvaluationError.invalidLine(evalErr.pInfo, evalErr)
            }
        } else {
            throw err
        }
    }

    private static func handleDirective(_ directive: ParserDirective, with ctx: GenerationContext) throws -> String? {
        if case let .excludeFile(filename) = directive {
            ctx.debugLog.excludingFile(filename)
            return nil
        } else if case let .stopRenderingCurrentFile(filename, pInfo) = directive {
            ctx.debugLog.stopRenderingCurrentFile(filename, pInfo: pInfo)
            return nil
        } else if case let .throwErrorFromCurrentFile(_, _, pInfo) = directive {
            throw EvaluationError.templateRenderingError(pInfo, directive)
        }

        throw directive
    }
}

public protocol TemplateSoupEvaluator {
    func execute(template: Template, with ctx: GenerationContext) async throws -> String?
}
