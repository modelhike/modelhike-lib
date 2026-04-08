//
//  ResourceBlueprint.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

private struct CachedResourceTemplateFile: Sendable {
    let templateName: String
    let outputNameTemplate: String
    let templateSource: TemplateExecutionSource
}

private struct CachedResourceStaticFile: Sendable {
    let filename: String
    let data: Data
}

private struct CachedResourceFilesetSubfolder: Sendable {
    let outputNameTemplate: String
    let fileset: CachedResourceFileset
}

private struct CachedResourceFileset: Sendable {
    let templateFiles: [CachedResourceTemplateFile]
    let staticFiles: [CachedResourceStaticFile]
    let subfolders: [CachedResourceFilesetSubfolder]
}

public actor ResourceBlueprint: Blueprint {
    private var templateCache: [String: Template] = [:]
    private var scriptFileCache: [String: Script] = [:]
    private var filesetCache: [String: CachedResourceFileset] = [:]

    public let context: GenerationContext

    public let blueprintName: String
    let bundle: Bundle
    public var blueprintPath: String
    public var resourceRoot: String

    private func bundleURL(forResource filename: String, withExtension ext: String?) -> URL? {
        let ns = filename as NSString
        let dir = ns.deletingLastPathComponent
        let base = ns.lastPathComponent
        let name: String
        let resolvedExt: String?
        if let ext {
            name = base
            resolvedExt = ext
        } else {
            let pathExt = (base as NSString).pathExtension
            name = (base as NSString).deletingPathExtension
            resolvedExt = pathExt.isEmpty ? TemplateConstants.TemplateExtension : pathExt
        }
        let subdir = dir.isEmpty ? blueprintPath : blueprintPath + dir + "/"
        return bundle.url(forResource: name, withExtension: resolvedExt, subdirectory: subdir)
    }

    public func loadScriptFile(fileName: String, with pInfo: ParsedInfo) async throws -> any Script {
        if let cached = scriptFileCache[fileName] { return cached }

        if let resourceURL = bundleURL(
            forResource: fileName,
            withExtension: TemplateConstants.ScriptExtension)
        {
            do {
                let content = try String(contentsOf: resourceURL)
                let template = StringTemplate(contents: content, name: fileName)
                self.scriptFileCache[fileName] = template
                return template
            } catch {
                throw TemplateSoup_EvaluationError.scriptFileReadingError(fileName, pInfo)
            }
        } else {
            throw TemplateSoup_EvaluationError.scriptFileDoesNotExist(fileName, pInfo)
        }

    }

    public func loadTemplate(fileName: String, with pInfo: ParsedInfo) throws -> Template {
        if let cached = templateCache[fileName] { return cached }

        if let resourceURL = bundleURL(
            forResource: fileName,
            withExtension: TemplateConstants.TemplateExtension)
        {
            do {
                let content = try String(contentsOf: resourceURL)
                let template = StringTemplate(contents: content, name: fileName)
                self.templateCache[fileName] = template
                return template
            } catch {
                throw TemplateSoup_EvaluationError.templateReadingError(fileName, pInfo)
            }
        } else {
            throw TemplateSoup_EvaluationError.templateDoesNotExist(fileName, pInfo)
        }

    }

    private func loadPathExists() -> Bool {
        do {
            let folder = blueprintPath
            guard let resourceURL = bundle.resourceURL?.appendingPathComponent(folder) else {
                return false
            }

            let fm = FileManager.default
            let resourcePaths = try fm.contentsOfDirectory(
                at: resourceURL, includingPropertiesForKeys: nil)

            return resourcePaths.count > 0
        } catch {
            return false
        }
    }

    public func exists() async throws -> Bool {
        if !loadPathExists() {
            let pInfo = await ParsedInfo.dummyForAppState(with: context)
            throw EvaluationError.invalidAppState(
                "Blueprint resource root folder was not found.", pInfo)
        }

        return hasFolder("")  //check blueprint path
    }

    public func hasFolder(_ foldername: String) -> Bool {
        do {
            let folder = blueprintPath + foldername
            guard let resourceURL = bundle.resourceURL?.appendingPathComponent(folder) else {
                return false
            }

            let fm = FileManager.default
            let resourcePaths = try fm.contentsOfDirectory(
                at: resourceURL, includingPropertiesForKeys: nil)

            return resourcePaths.count > 0
        } catch {
            return false
        }
    }

    public func hasFile(_ filename: String) -> Bool {
        bundleURL(forResource: filename, withExtension: nil) != nil
    }

    public func listFiles(inFolder foldername: String) -> [String] {
        let folder = blueprintPath + foldername
        guard let resourceURL = bundle.resourceURL?.appendingPathComponent(folder) else { return [] }

        let fm = FileManager.default
        do {
            let resourcePaths = try fm.contentsOfDirectory(
                at: resourceURL, includingPropertiesForKeys: nil)
            return resourcePaths.compactMap { url in
                let isDir = url.hasDirectoryPath 
                return isDir ? nil : url.lastPathComponent
            }
        } catch {
            return []
        }
    }

    public func copyFiles(foldername: String, to outputFolder: OutputFolder, with pInfo: ParsedInfo)
    async throws
    {
        let folder = blueprintPath + foldername
        guard let resourceURL = bundle.resourceURL?.appendingPathComponent(folder) else { return }

        try await copyResourceFiles(from: resourceURL, to: outputFolder, pInfo: pInfo)
    }

    fileprivate func copyResourceFiles(
        from resUrl: URL, to outputFolder: OutputFolder, pInfo: ParsedInfo
    ) async throws {
        let fm = FileManager.default

        do {
            let resourcePaths = try fm.contentsOfDirectory(
                at: resUrl, includingPropertiesForKeys: nil)
            for resourcePath in resourcePaths {
                let resourceName = resourcePath.lastPathComponent

                if !resourcePath.hasDirectoryPath {  //resource file
                    let contents = try Data(contentsOf: resourcePath)

                    let filename = resourceName
                    let outFile = StaticFile(filename: filename, data: contents, pInfo: pInfo )
                    await outputFolder.add(outFile)
                } else {  //resource folder
                    let newResUrl = resUrl.appendingPathComponent(resourceName)
                    try await copyResourceFiles(
                        from: newResUrl, to: outputFolder.subFolder(resourceName) , pInfo: pInfo)
                }
            }
        } catch {
            context.debugLog.pipelineError(String(describing: error))
            throw ResourceDoesNotExist(resName: resUrl.absoluteString, pInfo: pInfo)
        }
    }

    public func renderFiles(
        foldername: String, to outputFolder: OutputFolder, using templateSoup: TemplateSoup,
        with pInfo: ParsedInfo
    ) async throws {
        let folder = blueprintPath + foldername
        guard let resourceURL = bundle.resourceURL?.appendingPathComponent(folder) else { return }

        let fileset = try await cachedFileset(for: foldername, resourceURL: resourceURL, pInfo: pInfo)
        try await renderFileset(fileset, to: outputFolder, using: templateSoup, with: pInfo)
    }

    func cachedFilesetCount() -> Int {
        filesetCache.count
    }

    private func cachedFileset(for foldername: String, resourceURL: URL, pInfo: ParsedInfo) async throws -> CachedResourceFileset {
        if let cached = filesetCache[foldername] {
            return cached
        }

        let fileset = try await buildFileset(from: resourceURL, relativePath: foldername, pInfo: pInfo)
        filesetCache[foldername] = fileset
        return fileset
    }

    private func buildFileset(from resourceURL: URL, relativePath: String, pInfo: ParsedInfo) async throws -> CachedResourceFileset {
        let fm = FileManager.default
        var templateFiles: [CachedResourceTemplateFile] = []
        var staticFiles: [CachedResourceStaticFile] = []
        var subfolders: [CachedResourceFilesetSubfolder] = []

        do {
            let resourcePaths = try fm.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)
            
            for resourcePath in resourcePaths {
                let resourceName = resourcePath.lastPathComponent

                if !resourcePath.hasDirectoryPath {  //resource file
                    if resourceName.fileExtension() == TemplateConstants.TemplateExtension {  //if tempalte file

                        let templateName = resourceName.withoutFileExtension()
                        let templateIdentifier = relativePath.isEmpty ? templateName : "\(relativePath)/\(templateName)"
                        let templateSource = TemplateExecutionSource.parse(
                            contents: try String(contentsOf: resourcePath),
                            identifier: templateIdentifier,
                            parseFrontMatter: true
                        )
                        templateFiles.append(
                            CachedResourceTemplateFile(
                                templateName: templateName,
                                outputNameTemplate: templateName,
                                templateSource: templateSource
                            )
                        )
                    } else {  //not a template file
                        staticFiles.append(CachedResourceStaticFile(filename: resourceName, data: try Data(contentsOf: resourcePath)))
                    }
                } else {  //resource folder
                    let relativeSubfolder = relativePath.isEmpty ? resourceName : "\(relativePath)/\(resourceName)"
                    let subfileset = try await buildFileset(from: resourcePath, relativePath: relativeSubfolder, pInfo: pInfo)
                    subfolders.append(CachedResourceFilesetSubfolder(outputNameTemplate: resourceName, fileset: subfileset))
                }
            }
        } catch {
            context.debugLog.pipelineError(String(describing: error))
            throw ResourceDoesNotExist(resName: resourceURL.absoluteString, pInfo: pInfo)
        }

        return CachedResourceFileset(templateFiles: templateFiles, staticFiles: staticFiles, subfolders: subfolders)
    }

    private func renderFileset(
        _ fileset: CachedResourceFileset,
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
            await templateSoup.context.debugLog.copyingFileInFolder(file.filename, folder: outputFolder.folder)
            let outFile = StaticFile(filename: file.filename, data: file.data, pInfo: pInfo)
            await outputFolder.add(outFile)
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
        _ templateFile: CachedResourceTemplateFile,
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
        if let resourceURL = bundleURL(forResource: filename, withExtension: nil) {
            do {
                let content = try String(contentsOf: resourceURL)
                return content
            } catch {
                throw ResourceReadingError(resName: filename, pInfo: pInfo)
            }
        } else {
            throw ResourceDoesNotExist(resName: filename, pInfo: pInfo)
        }
    }

    public init(
        blueprint: String, blueprintsRoot: String, resourceRoot: String, bundle: Bundle,
        with ctx: GenerationContext
    ) {
        self.bundle = bundle
        self.blueprintName = blueprint
        self.blueprintPath = "\(blueprintsRoot)\(blueprint)/"
        self.resourceRoot = resourceRoot
        self.context = ctx
    }

}

public struct ResourceReadingError: ErrorWithMessageAndParsedInfo, ErrorCodeProviding {
    let resName: String
    public let pInfo: ParsedInfo

    public var info: String {
        return "Resource \(resName) reading error."
    }

    public var errorCode: String { "E701" }

    public init(resName: String, pInfo: ParsedInfo) {
        self.resName = resName
        self.pInfo = pInfo
    }
}

public struct ResourceDoesNotExist: ErrorWithMessageAndParsedInfo, ErrorCodeProviding {
    let resName: String
    public let pInfo: ParsedInfo

    public var info: String {
        return "Resource \(resName) does not exist."
    }

    public var errorCode: String { "E702" }

    public init(resName: String, pInfo: ParsedInfo) {
        self.resName = resName
        self.pInfo = pInfo
    }
}
