//
//  InlineBlueprint.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

/// An in-memory `Blueprint` for use in unit tests.
/// Mirrors the role of `InlineModelLoader` for the model layer.
///
/// ```swift
/// let blueprint = InlineBlueprint(name: "api-blueprint") {
///     InlineScript("main", contents: ":render file \"Entity.teso\"")
///
///     InlineFolder("_root_") {
///         InlineTemplate("Entity", contents: "class {{ entity.name }} {}")
///     }
///
///     InlineModifier("javaType", contents: """
///         ---
///         input: prop
///         type: Object
///         ---
///         String
///         """)
/// }
/// ```
public actor InlineBlueprint: Blueprint {
    public let blueprintName: String

    /// `[foldername: [filename_with_ext: contents]]` — root items use key `""`.
    private let folderMap: [String: [String: String]]

    // MARK: Blueprint

    public func exists() async throws -> Bool { true }

    public func loadTemplate(fileName: String, with pInfo: ParsedInfo) async throws -> Template {
        let (folder, fname) = Self.resolveLogicalPath(fileName, extension: TemplateConstants.TemplateExtension)
        guard let contents = folderMap[folder]?[fname] else {
            throw TemplateSoup_EvaluationError.templateDoesNotExist(fileName, pInfo)
        }
        let baseName = (fname as NSString).deletingPathExtension
        return StringTemplate(contents: contents, name: baseName)
    }

    public func loadScriptFile(fileName: String, with pInfo: ParsedInfo) async throws -> any Script {
        let (folder, fname) = Self.resolveLogicalPath(fileName, extension: TemplateConstants.ScriptExtension)
        guard let contents = folderMap[folder]?[fname] else {
            throw TemplateSoup_EvaluationError.scriptFileDoesNotExist(fileName, pInfo)
        }
        let baseName = (fname as NSString).deletingPathExtension
        return StringTemplate(contents: contents, name: baseName)
    }

    // MARK: InputFileRepository

    public func readTextContents(filename: String, with pInfo: ParsedInfo) async throws -> String {
        let (folder, file) = Self.splitPathLast(filename)
        guard let contents = folderMap[folder]?[file] else {
            throw TemplateSoup_EvaluationError.templateReadingError(filename, pInfo)
        }
        return contents
    }

    public func hasFolder(_ foldername: String) async -> Bool {
        folderMap[foldername] != nil
    }

    public func hasFile(_ filename: String) -> Bool {
        let (folder, file) = Self.splitPathLast(filename)
        return folderMap[folder]?[file] != nil
    }

    public func listFiles(inFolder foldername: String) async -> [String] {
        guard let files = folderMap[foldername] else { return [] }
        return Array(files.keys)
    }

    public func copyFiles(foldername: String, to folder: OutputFolder, with pInfo: ParsedInfo) async throws {
        if let files = folderMap[foldername] {
            for (filename, contents) in files {
                guard !filename.hasSuffix(".\(TemplateConstants.TemplateExtension)") else { continue }
                let outFile = StaticFile(filename: filename, contents: contents, pInfo: pInfo)
                await folder.add(outFile)
            }
        }
        for childName in Self.directChildSubfolderNames(of: foldername, in: folderMap) {
            let fullChildKey = Self.childFolderKey(parent: foldername, childName: childName)
            let newFolder = await folder.subFolder(childName)
            try await copyFiles(foldername: fullChildKey, to: newFolder, with: pInfo)
        }
    }

    public func renderFiles(
        foldername: String, to outputFolder: OutputFolder,
        using templateSoup: TemplateSoup, with pInfo: ParsedInfo
    ) async throws {
        try await renderFileset(foldername: foldername, to: outputFolder, using: templateSoup, with: pInfo)
    }

    // MARK: Init

    public init(
        name: String = "inline-blueprint",
        @InlineBlueprintItemBuilder _ builder: () -> [any InlineBlueprintItem]
    ) {
        self.blueprintName = name
        var map: [String: [String: String]] = [:]
        for item in builder() {
            var folderFiles = map[item.foldername] ?? [:]
            folderFiles[item.filename] = item.contents
            map[item.foldername] = folderFiles
        }
        self.folderMap = map
    }

    /// Raw-map initializer for deserialization / JSON round-trips without going through the result builder.
    public init(name: String, folderMap: [String: [String: String]]) {
        self.blueprintName = name
        self.folderMap = folderMap
    }

    public func toSnapshot() -> InlineBlueprintSnapshot {
        InlineBlueprintSnapshot(name: blueprintName, files: folderMap)
    }

    public func toJSON(prettyPrinted: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(toSnapshot())
        return String(decoding: data, as: UTF8.self)
    }

    public static func fromJSON(_ json: String) throws -> InlineBlueprint {
        try fromJSON(Data(json.utf8))
    }

    public static func fromJSON(_ data: Data) throws -> InlineBlueprint {
        let snapshot = try JSONDecoder().decode(InlineBlueprintSnapshot.self, from: data)
        return snapshot.toInlineBlueprint()
    }

    // MARK: Private — parity with LocalFileBlueprint folder rendering

    private func renderFileset(
        foldername: String,
        to outputFolder: OutputFolder,
        using templateSoup: TemplateSoup,
        with pInfo: ParsedInfo
    ) async throws {
        if let files = folderMap[foldername] {
            let hasStaticFiles = files.keys.contains { !$0.hasSuffix(".\(TemplateConstants.TemplateExtension)") }
            if hasStaticFiles {
                try await outputFolder.ensureExists()
            }
            for (filename, contents) in files {
                if filename.hasSuffix(".\(TemplateConstants.TemplateExtension)") {
                    let templateName = String(filename.dropLast(".\(TemplateConstants.TemplateExtension)".count))
                    let templateIdentifier = foldername.isEmpty ? templateName : "\(foldername)/\(templateName)"
                    let templateSource = TemplateExecutionSource.parse(
                        contents: contents,
                        identifier: templateIdentifier,
                        parseFrontMatter: true
                    )
                    try await renderInlineTemplateFile(
                        templateName: templateName,
                        outputNameTemplate: templateName,
                        templateSource: templateSource,
                        to: outputFolder,
                        using: templateSoup,
                        with: pInfo
                    )
                } else {
                    await templateSoup.context.debugLog.copyingFileInFolder(filename, folder: outputFolder.folder)
                    let outFile = StaticFile(filename: filename, contents: contents, pInfo: pInfo)
                    await outputFolder.add(outFile)
                }
            }
        }

        for childName in Self.directChildSubfolderNames(of: foldername, in: folderMap) {
            let fullChildKey = Self.childFolderKey(parent: foldername, childName: childName)
            let subfoldername = try await ContentHandler.evalIfNeeded(expression: childName, with: templateSoup.context)
                ?? childName
            let newFolder = await outputFolder.subFolder(subfoldername)
            try await renderFileset(foldername: fullChildKey, to: newFolder, using: templateSoup, with: pInfo)
        }
    }

    /// Mirrors ``LocalFileBlueprint/renderTemplateFile`` using ``TemplateSoup``’s internal `renderTemplate(source:…)`.
    private func renderInlineTemplateFile(
        templateName: String,
        outputNameTemplate: String,
        templateSource: TemplateExecutionSource,
        to outputFolder: OutputFolder,
        using templateSoup: TemplateSoup,
        with pInfo: ParsedInfo
    ) async throws {
        let ctx = templateSoup.context
        let filename = try await ContentHandler.evalIfNeeded(expression: outputNameTemplate, with: ctx)
            ?? outputNameTemplate
        let parsingIdentifier = templateName
        let parsingFrontMatter = templateSource.frontMatter?.withIdentifier(parsingIdentifier)
        let includeForInfo: ParsedInfo? = if let parsingFrontMatter {
            await FrontMatter.hasDirective(ParserDirective.includeFor, in: parsingFrontMatter, with: ctx)
        } else {
            nil
        }
        let hasOutputFilename = if let parsingFrontMatter {
            await FrontMatter.hasDirective(ParserDirective.outputFilename, in: parsingFrontMatter, with: ctx) != nil
        } else {
            false
        }

        let renderClosure: RenderClosure = { outputname, renderPInfo in
            do {
                let outputFilename = outputname.isNotEmpty ? outputname : filename
                if try await !ctx.events.canRender(filename: outputFilename, templatename: templateName, with: renderPInfo) {
                    return
                }
                if let renderedString = try await templateSoup.renderTemplate(
                    source: templateSource,
                    with: renderPInfo,
                    frontMatterIdentifier: filename
                ) {
                    await ctx.debugLog.generatingFileInFolder(
                        filename,
                        with: templateName,
                        folder: outputFolder.folder,
                        pInfo: renderPInfo
                    )
                    let outFile = TemplateRenderedFile(filename: outputFilename, contents: renderedString, pInfo: renderPInfo)
                    await outputFolder.add(outFile)
                }
            } catch let err {
                if let directive = err as? ParserDirective {
                    if case let .excludeFile(filename) = directive {
                        await renderPInfo.ctx.debugLog.excludingFile(filename)
                        return
                    } else if case let .stopRenderingCurrentFile(filename, pInfo) = directive {
                        await renderPInfo.ctx.debugLog.stopRenderingCurrentFile(filename, pInfo: pInfo)
                        return
                    } else if case let .throwErrorFromCurrentFile(filename, errMsg, pInfo) = directive {
                        await renderPInfo.ctx.debugLog.throwErrorFromCurrentFile(filename, err: errMsg, pInfo: pInfo)
                        throw EvaluationError.templateRenderingError(pInfo, directive)
                    }
                } else {
                    throw err
                }
            }
        }

        if let includeForInfo, let parsingFrontMatter {
            try await templateSoup.forEach(forInExpression: includeForInfo.line, with: includeForInfo) {
                if hasOutputFilename {
                    if let outputFilename = try await FrontMatter.evalDirective(ParserDirective.outputFilename, in: parsingFrontMatter, pInfo: includeForInfo) as? String {
                        try await renderClosure(outputFilename, includeForInfo)
                    }
                } else {
                    try await renderClosure("", includeForInfo)
                }
            }
        } else {
            let renderPInfo = await ParsedInfo.dummyForFrontMatterError(identifier: parsingIdentifier, with: ctx)
            try await renderClosure("", renderPInfo)
        }
    }

    /// `"folder/path"` → `("folder", "path")` using the last path separator (supports nested folders).
    private static func splitPathLast(_ path: String) -> (folder: String, file: String) {
        guard let idx = path.lastIndex(of: "/") else { return ("", path) }
        return (String(path[..<idx]), String(path[path.index(after: idx)...]))
    }

    private static func resolveLogicalPath(_ logicalPath: String, extension ext: String) -> (folder: String, filename: String) {
        let ns = logicalPath as NSString
        let dir = ns.deletingLastPathComponent
        let base = ns.lastPathComponent
        let folder = dir == "." ? "" : dir
        let filename: String
        if (base as NSString).pathExtension.isEmpty {
            filename = "\(base).\(ext)"
        } else {
            filename = base
        }
        return (folder, filename)
    }

    private static func directChildSubfolderNames(of parent: String, in folderMap: [String: [String: String]]) -> [String] {
        let prefix = parent.isEmpty ? "" : parent + "/"
        var names = Set<String>()
        for key in folderMap.keys {
            guard key != parent, key.hasPrefix(prefix) else { continue }
            let remainder = String(key.dropFirst(prefix.count))
            guard !remainder.contains("/") else { continue }
            names.insert(remainder)
        }
        return names.sorted()
    }

    private static func childFolderKey(parent: String, childName: String) -> String {
        parent.isEmpty ? childName : "\(parent)/\(childName)"
    }
}

// MARK: - Item protocol

/// Represents a single in-memory file inside a blueprint (template, script, or modifier).
public protocol InlineBlueprintItem: Sendable {
    /// Folder within the blueprint. Use `""` for root-level files.
    var foldername: String { get }
    /// Filename including extension (e.g. `"main.teso"`, `"main.ss"`).
    var filename: String { get }
    var contents: String { get }
}

// MARK: - Concrete item types

/// An in-memory `.teso` template file at the blueprint root (or an explicit folder).
/// The `.teso` extension is appended automatically.
public struct InlineTemplate: InlineBlueprintItem {
    public let foldername: String
    public let filename: String
    public let contents: String

    public init(_ name: String, in folder: String = "", contents: String) {
        self.foldername = folder
        self.filename   = "\(name).\(TemplateConstants.TemplateExtension)"
        self.contents   = contents
    }
}

/// An in-memory `.ss` script file at the blueprint root (or an explicit folder).
/// The `.ss` extension is appended automatically.
public struct InlineScript: InlineBlueprintItem {
    public let foldername: String
    public let filename: String
    public let contents: String

    public init(_ name: String, in folder: String = "", contents: String) {
        self.foldername = folder
        self.filename   = "\(name).\(TemplateConstants.ScriptExtension)"
        self.contents   = contents
    }
}

/// Shorthand for a blueprint-defined modifier: a `.teso` file placed in `_modifiers_`.
/// The `.teso` extension is appended automatically.
///
/// Example:
/// ```swift
/// InlineModifier("javaType", contents: """
///     ---
///     input: prop
///     type: Object
///     ---
///     String
///     """)
/// ```
public struct InlineModifier: InlineBlueprintItem {
    public let foldername = SpecialFolderNames.modifiers
    public let filename: String
    public let contents: String

    public init(_ name: String, contents: String) {
        self.filename = "\(name).\(TemplateConstants.TemplateExtension)"
        self.contents = contents
    }
}

/// An in-memory static (non-template) file — full filename including extension.
public struct InlineStaticFile: InlineBlueprintItem {
    public let foldername: String
    public let filename: String
    public let contents: String

    public init(_ name: String, in folder: String = "", contents: String) {
        self.foldername = folder
        self.filename = name
        self.contents = contents
    }
}

/// Groups multiple inline items under a named sub-folder of the blueprint.
///
/// Example:
/// ```swift
/// InlineFolder("_root_") {
///     InlineTemplate("Entity", contents: "class {{ entity.name }} {}")
/// }
/// ```
public struct InlineFolder: Sendable {
    fileprivate let items: [any InlineBlueprintItem]

    public init(_ name: String, @InlineBlueprintItemBuilder _ builder: () -> [any InlineBlueprintItem]) {
        self.items = builder().map { FolderScopedItem(foldername: name, from: $0) }
    }
}

/// Private wrapper that overrides `foldername` on an existing item.
private struct FolderScopedItem: InlineBlueprintItem {
    let foldername: String
    let filename: String
    let contents: String

    init(foldername: String, from item: any InlineBlueprintItem) {
        if item.foldername.isEmpty {
            self.foldername = foldername
        } else {
            self.foldername = "\(foldername)/\(item.foldername)"
        }
        self.filename = item.filename
        self.contents = item.contents
    }
}

// MARK: - Builder

/// A result builder that accepts `InlineBlueprintItem`-conforming values **and**
/// `InlineFolder` containers (which expand to multiple items with a shared folder name).
@resultBuilder
public struct InlineBlueprintItemBuilder {
    public static func buildBlock(_ components: [any InlineBlueprintItem]...) -> [any InlineBlueprintItem] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: any InlineBlueprintItem) -> [any InlineBlueprintItem] {
        [expression]
    }

    public static func buildExpression(_ expression: InlineFolder) -> [any InlineBlueprintItem] {
        expression.items
    }

    public static func buildOptional(_ component: [any InlineBlueprintItem]?) -> [any InlineBlueprintItem] {
        component ?? []
    }

    public static func buildEither(first component: [any InlineBlueprintItem]) -> [any InlineBlueprintItem] {
        component
    }

    public static func buildEither(second component: [any InlineBlueprintItem]) -> [any InlineBlueprintItem] {
        component
    }

    public static func buildArray(_ components: [[any InlineBlueprintItem]]) -> [any InlineBlueprintItem] {
        components.flatMap { $0 }
    }
}


