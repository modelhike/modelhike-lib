//
//  LocalFileBlueprint.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public actor LocalFileBlueprint: Blueprint {
    private var templateCache: [String: Template] = [:]
    private var scriptFileCache: [String: Script] = [:]
    private var filesetCache: [String: LocalFilesetTemplate] = [:]

    public let blueprintPath: LocalPath
    public let rootPath: LocalPath
    public let context: GenerationContext
    public var paths: [LocalPath]
    public let blueprintName: String

    private func resolvedFilename(for filename: String, withExtension ext: String? = nil) -> String {
        let ns = filename as NSString
        let dir = ns.deletingLastPathComponent
        let base = ns.lastPathComponent
        let pathExt = (base as NSString).pathExtension
        let resolvedBase: String
        if let ext {
            resolvedBase = pathExt == ext ? base : "\(base).\(ext)"
        } else {
            resolvedBase = pathExt.isEmpty ? "\(base).\(TemplateConstants.TemplateExtension)" : base
        }
        return dir.isEmpty ? resolvedBase : "\(dir)/\(resolvedBase)"
    }

    public func loadScriptFile(fileName: String, with pInfo: ParsedInfo) async throws -> any Script {
        if let cached = scriptFileCache[fileName] { return cached }

        for loadPath in paths {
            if !loadPath.exists {
                let pInfo = await ParsedInfo.dummyForAppState(with: context)
                throw EvaluationError.invalidAppState(
                    "Blueprint folder '\(loadPath.string)' was not found.", pInfo)
            }

            let scriptFilePath = loadPath / resolvedFilename(
                for: fileName,
                withExtension: TemplateConstants.ScriptExtension
            )

            if !scriptFilePath.exists { continue }  //check if found in next oath

            let file = LocalFile(path: scriptFilePath)

            if let script = LocalScriptFile(file: file) {
                self.scriptFileCache[fileName] = script
                return script
            } else {
                throw TemplateSoup_EvaluationError.scriptFileReadingError(fileName, pInfo)
            }
        }

        throw TemplateSoup_EvaluationError.scriptFileDoesNotExist(fileName, pInfo)
    }

    public func loadTemplate(fileName: String, with pInfo: ParsedInfo) async throws -> Template {
        if let cached = templateCache[fileName] { return cached }

        for loadPath in paths {
            if !loadPath.exists {
                let pInfo = await ParsedInfo.dummyForAppState(with: context)
                throw EvaluationError.invalidAppState(
                    "Blueprint folder '\(loadPath.string)' was not found.", pInfo)
            }

            let templatePath = loadPath / resolvedFilename(
                for: fileName,
                withExtension: TemplateConstants.TemplateExtension
            )

            if !templatePath.exists { continue }  //check if found in next oath

            let file = LocalFile(path: templatePath)

            if let template = LocalFileTemplate(file: file) {
                self.templateCache[fileName] = template
                return template
            } else {
                throw TemplateSoup_EvaluationError.templateReadingError(fileName, pInfo)
            }
        }

        throw TemplateSoup_EvaluationError.templateDoesNotExist(fileName, pInfo)
    }

    private func loadPathExists() -> Bool {
        return rootPath.exists
    }

    public func exists() async throws -> Bool {
        if !loadPathExists() {
            let pInfo = await ParsedInfo.dummyForAppState(with: context)
            throw EvaluationError.invalidAppState(
                "Blueprint root folder '\(rootPath.string)' was not found.", pInfo)
        }

        return self.blueprintPath.exists
    }

    public func hasFolder(_ foldername: String) -> Bool {
        guard self.blueprintPath.exists else {
            return false
        }

        let inFolder = LocalFolder(path: self.blueprintPath / foldername)
        return inFolder.path.exists
    }

    public func hasFile(_ filename: String) -> Bool {
        guard self.blueprintPath.exists else {
            return false
        }

        return (self.blueprintPath / resolvedFilename(for: filename)).exists
    }

    public func listFiles(inFolder foldername: String) -> [String] {
        let folder = LocalFolder(path: self.blueprintPath / foldername)
        guard folder.path.exists else { return [] }
        return folder.files.map { $0.name }
    }

    public func copyFiles(foldername: String, to outputFolder: OutputFolder, with pInfo: ParsedInfo)
    async throws
    {
        guard self.blueprintPath.exists else {
            throw EvaluationError.invalidInput(
                "There is no folder called \(self.blueprintPath.string)", pInfo)
        }

        do {
            let inFolder = LocalFolder(path: self.blueprintPath / foldername)
            try await copyLocalFiles(from: inFolder, to: outputFolder, with: pInfo)
            
        } catch let err {
            if err as? ErrorWithMessageAndParsedInfo != nil {
                throw err
            } else {
                let message =
                "Could not copy files from \(foldername) to \(await outputFolder.path.string)"
                throw EvaluationError.failedWriteOperation(message, pInfo)
            }
        }
    }

    private func copyLocalFiles(from inFolder: LocalFolder, to outputFolder: OutputFolder, with pInfo: ParsedInfo) async throws
    {

        for file in inFolder.files {
            let copyFile = FileToCopy(file: file, pInfo: pInfo)
            await outputFolder.add(copyFile)
        }
        
        //copy files from subfolders also
        for subFolder in inFolder.subFolders {
            let outputSubFolder = await outputFolder.subFolder(subFolder.name)
            try await copyLocalFiles(from: subFolder, to: outputSubFolder, with: pInfo)
        }
    }
    
    public func renderFiles(
        foldername: String, to outputFolder: OutputFolder, using templateSoup: TemplateSoup,
        with pInfo: ParsedInfo
    ) async throws {
        guard self.blueprintPath.exists else {
            throw EvaluationError.invalidInput(
                "There is no folder called \(self.blueprintPath.string)", pInfo)
        }

        do {
            let fileset = try cachedFileset(for: foldername)
            try await renderFileset(fileset, to: outputFolder, using: templateSoup, with: pInfo)
        } catch let err {
            if err as? ErrorWithMessageAndParsedInfo != nil {
                throw err
            } else {
                let message =
                "Could not render files from \(foldername) to \(await outputFolder.path.string)"
                throw EvaluationError.failedWriteOperation(message, pInfo)
            }
        }
    }

    func cachedFilesetCount() -> Int {
        filesetCache.count
    }

    private func cachedFileset(for foldername: String) throws -> LocalFilesetTemplate {
        if let cached = filesetCache[foldername] {
            return cached
        }

        let folder = LocalFolder(path: blueprintPath / foldername)
        let fileset = try buildFileset(from: folder, relativePath: foldername)
        filesetCache[foldername] = fileset
        return fileset
    }

    private func buildFileset(from folder: LocalFolder, relativePath: String) throws -> LocalFilesetTemplate {
        let files = folder.files
        var templateFiles: [CachedLocalTemplateFile] = []
        var staticFiles: [LocalFile] = []
        var subfolders: [CachedLocalFilesetSubfolder] = []

        for file in files {
            if file.extension == TemplateConstants.TemplateExtension {
                let templateName = file.nameExcludingExtension
                let templateIdentifier = relativePath.isEmpty ? templateName : "\(relativePath)/\(templateName)"
                let templateSource = TemplateExecutionSource.parse(
                    contents: try file.readTextContents(),
                    identifier: templateIdentifier,
                    parseFrontMatter: true
                )
                templateFiles.append(
                    CachedLocalTemplateFile(
                        file: file,
                        outputNameTemplate: templateName,
                        templateName: templateName,
                        templateSource: templateSource
                    )
                )
            } else {
                staticFiles.append(file)
            }
        }

        for subFolder in folder.subFolders {
            let relativeSubfolder = relativePath.isEmpty ? subFolder.name : "\(relativePath)/\(subFolder.name)"
            let subfileset = try buildFileset(from: subFolder, relativePath: relativeSubfolder)
            subfolders.append(CachedLocalFilesetSubfolder(outputNameTemplate: subFolder.name, fileset: subfileset))
        }

        return LocalFilesetTemplate(
            name: folder.name,
            files: files,
            templateFiles: templateFiles,
            staticFiles: staticFiles,
            subfolders: subfolders
        )
    }

    private func renderFileset(
        _ fileset: LocalFilesetTemplate,
        to outputFolder: OutputFolder,
        using templateSoup: TemplateSoup,
        with pInfo: ParsedInfo
    ) async throws {
        for templateFile in fileset.templateFiles {
            try await renderTemplateFile(templateFile, to: outputFolder, using: templateSoup, with: pInfo)
        }

        //create the folder only if any file is copied
        if fileset.staticFiles.isNotEmpty {
            try await outputFolder.ensureExists()
        }
        
        for file in fileset.staticFiles {
            await templateSoup.context.debugLog.copyingFileInFolder(file.name, folder: outputFolder.folder)
            let copyFile = FileToCopy(file: file, pInfo: pInfo)
            await outputFolder.add(copyFile)
        }

        //copy files from subfolders also
        for subfolder in fileset.subfolders {
            //render the foldername if it has an expression within '{{' and '}}'
            let subfoldername = try await ContentHandler.evalIfNeeded(expression: subfolder.outputNameTemplate, with: templateSoup.context)
                ?? subfolder.outputNameTemplate
            let newFolder = await outputFolder.subFolder(subfoldername)
            try await renderFileset(subfolder.fileset, to: newFolder, using: templateSoup, with: pInfo)
        }
    }

    private func renderTemplateFile(
        _ templateFile: CachedLocalTemplateFile,
        to outputFolder: OutputFolder,
        using templateSoup: TemplateSoup,
        with pInfo: ParsedInfo
    ) async throws {
        //render the filename if it has an expression within '{{' and '}}'
        let filename = try await ContentHandler.evalIfNeeded(expression: templateFile.outputNameTemplate, with: templateSoup.context)
            ?? templateFile.outputNameTemplate
        let parsingIdentifier = templateFile.templateName
        let parsingFrontMatter = templateFile.templateSource.frontMatter?.withIdentifier(parsingIdentifier)
        let includeForInfo: ParsedInfo? = if let parsingFrontMatter {
            await FrontMatter.hasDirective(ParserDirective.includeFor, in: parsingFrontMatter, with: templateSoup.context)
        } else {
            nil
        }
        let hasOutputFilename = if let parsingFrontMatter {
            await FrontMatter.hasDirective(ParserDirective.outputFilename, in: parsingFrontMatter, with: templateSoup.context) != nil
        } else {
            false
        }

        let renderClosure: RenderClosure = { [self] outputname, renderPInfo in
            do {
                let outputFilename = outputname.isNotEmpty ? outputname : filename
                //if handler returns false, dont render file
                if try await !self.context.events.canRender(filename: outputFilename, templatename: templateFile.templateName, with: renderPInfo) {
                    return
                }

                //check if parser directives to exclude file
                if let renderedString = try await templateSoup.renderTemplate(
                    source: templateFile.templateSource,
                    with: renderPInfo,
                    frontMatterIdentifier: filename
                ) {
                    await templateSoup.context.debugLog.generatingFileInFolder(
                        filename,
                        with: templateFile.templateName,
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
                        return  //nothing to generate from this excluded file
                    } else if case let .stopRenderingCurrentFile(filename, pInfo) = directive {
                        await renderPInfo.ctx.debugLog.stopRenderingCurrentFile(filename, pInfo: pInfo)
                        return  //nothing to generate from this rendering stopped file
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
                    // ← if evalDirective returns nil, no renderClosure at all — file silently dropped
                } else {
                    try await renderClosure("", includeForInfo)
                }
            }
        } else {
            let renderPInfo = await ParsedInfo.dummyForFrontMatterError(identifier: parsingIdentifier, with: context)
            try await renderClosure("", renderPInfo)
        }
    }

    public func readTextContents(filename: String, with pInfo: ParsedInfo) throws -> String {
        guard self.blueprintPath.exists else {
            throw EvaluationError.invalidInput(
                "There is no folder called \(self.blueprintPath.string)", pInfo)
        }

        let inFile = LocalFile(path: self.blueprintPath / resolvedFilename(for: filename))
        let inFileContents = try inFile.readTextContents()
        return inFileContents
    }

    public func add(paths: LocalPath...) {
        self.paths.append(contentsOf: paths)
    }

    public func add(paths: [LocalPath]) {
        self.paths.append(contentsOf: paths)
    }

    public init(blueprint: String, path templatesPath: LocalPath, with ctx: GenerationContext) {
        let path = templatesPath / blueprint

        self.paths = [path]
        self.context = ctx
        self.blueprintPath = path
        self.blueprintName = blueprint
        self.rootPath = templatesPath
    }

    internal init(path: LocalPath, with ctx: GenerationContext) {
        self.paths = [path]
        self.context = ctx
        self.blueprintPath = path
        self.rootPath = path
        self.blueprintName = ""
    }
}
