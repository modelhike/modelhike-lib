//
//  LocalFilesetTemplate.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

/// Cached metadata for one template file inside a local blueprint folder.
/// The template body/front matter is pre-split so repeated `render-folder`
/// calls can skip re-reading and re-parsing the source file.
struct CachedLocalTemplateFile: Sendable {
    let file: LocalFile
    let outputNameTemplate: String
    let templateName: String
    let templateSource: TemplateExecutionSource
}

/// Cached nested folder entry. `outputNameTemplate` may still be dynamic even
/// though the child fileset contents are already materialized.
struct CachedLocalFilesetSubfolder: Sendable {
    let outputNameTemplate: String
    let fileset: LocalFilesetTemplate
}

/// In-memory representation of a local blueprint folder used by `render-folder`
/// caching. The raw `files` list is preserved, while templates/static files and
/// subfolders are also split into cache-friendly buckets for fast reuse.
public struct LocalFilesetTemplate: ScriptedTemplate {
    public private(set) var name: String
    public let files: [LocalFile]
    let templateFiles: [CachedLocalTemplateFile]
    let staticFiles: [LocalFile]
    let subfolders: [CachedLocalFilesetSubfolder]

    public func toString() -> String {
        name
    }

    public init(folderPath: String) {
        let folder = LocalFolder(path: folderPath)

        self.files = folder.files
        self.name = folder.name
        self.templateFiles = []
        self.staticFiles = []
        self.subfolders = []
    }

    init(
        name: String, files: [LocalFile], templateFiles: [CachedLocalTemplateFile],
        staticFiles: [LocalFile], subfolders: [CachedLocalFilesetSubfolder]
    ) {
        self.name = name
        self.files = files
        self.templateFiles = templateFiles
        self.staticFiles = staticFiles
        self.subfolders = subfolders
    }
}
