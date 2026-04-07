//
//  RenderedOutputSnapshot.swift
//  ModelHike
//

import Foundation

/// Serializable snapshot of one rendered output file kept in memory after generation.
/// This is used by the debug console to display generated output directly from the
/// pipeline's output tree without re-reading files back from disk.
public struct RenderedOutputRecord: Codable, Sendable {
    /// Full output path for the generated artifact.
    public let path: String
    /// In-memory rendered contents of that artifact.
    public let content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

extension PipelineState {
    /// Collects rendered output from every generation sandbox created during the run.
    /// Each sandbox owns a root `OutputFolder` tree, and this method flattens those
    /// trees into plain records that the debug server can serve to the browser UI.
    public func renderedOutputRecords() async -> [RenderedOutputRecord] {
        var records: [RenderedOutputRecord] = []

        for sandbox in generationSandboxes {
            let outputFolder = await sandbox.base_generation_dir
            records.append(contentsOf: await outputFolder.renderedOutputRecords())
        }

        return records
    }
}

// MARK: - OutputFolder in-memory content (debug UI + tests)

extension OutputFolder {

    /// Collects text contents for output files in this folder (recursively), without persisting to disk.
    ///
    /// Includes ``TemplateRenderedFile``, ``StaticFile``, ``PlaceHolderFile``, and ``OutputDocumentFile``
    /// when those files already hold in-memory output content.
    /// Keys are relative paths using `/` (e.g. `Subdir/file.txt`).
    /// Includes subtrees under ``PersistableFolder`` entries (``RenderedFolder``, ``StaticFolder``).
    public func snapshot(prefix: String = "") async -> [String: String] {
        var result: [String: String] = [:]
        for item in items {
            guard let pair = await Self.inMemoryContentPair(for: item) else { continue }
            let key: String
            if prefix.isEmpty {
                key = pair.name
            } else {
                key = "\(prefix)/\(pair.name)"
            }
            result[key] = pair.text
        }
        for folderItem in folderItems {
            let nestedOut: OutputFolder?
            let newName: String
            if let rendered = folderItem as? RenderedFolder {
                nestedOut = await rendered.outputFolder
                newName = rendered.newFoldername
            } else if let staticFolder = folderItem as? StaticFolder {
                nestedOut = await staticFolder.outputFolder
                newName = staticFolder.newFoldername
            } else {
                continue
            }
            guard let nestedOut else { continue }
            let nextPrefix: String
            if newName == "/" || newName.isEmpty {
                nextPrefix = prefix
            } else if prefix.isEmpty {
                nextPrefix = newName
            } else {
                nextPrefix = "\(prefix)/\(newName)"
            }
            let nested = await nestedOut.snapshot(prefix: nextPrefix)
            for (k, v) in nested {
                result[k] = v
            }
        }
        for sub in subFolders {
            let subName = await sub.foldername
            let nextPrefix = prefix.isEmpty ? subName : "\(prefix)/\(subName)"
            let nested = await sub.snapshot(prefix: nextPrefix)
            for (k, v) in nested {
                result[k] = v
            }
        }
        return result
    }

    /// Recursively walks this output folder and all nested output folders, extracting
    /// any generated file contents that are still available in memory.
    public func renderedOutputRecords() async -> [RenderedOutputRecord] {
        let rootPath = path
        var records: [RenderedOutputRecord] = []
        for (relativePath, content) in await snapshot() {
            records.append(RenderedOutputRecord(path: (rootPath / relativePath).string, content: content))
        }
        return records
    }

    /// Shared payload reader for ``snapshot(prefix:)`` and ``renderedOutputRecords()``.
    /// Assumes output files were already materialized into memory before being added.
    private static func inMemoryContentPair(for item: OutputFile) async -> (name: String, text: String)? {
        if let rendered = item as? TemplateRenderedFile {
            guard let contents = await rendered.contents else { return nil }
            return (rendered.filename, contents)
        }
        if let staticFile = item as? StaticFile {
            let contents = await staticFile.contents
            let data = await staticFile.data
            let text = contents ?? data.map { String(data: $0, encoding: .utf8) ?? $0.base64EncodedString() }
            guard let text else { return nil }
            return (staticFile.filename, text)
        }
        if let ph = item as? PlaceHolderFile {
            let text = await ph.contents
            guard let text else { return nil }
            return (ph.filename, text)
        }
        if let doc = item as? OutputDocumentFile {
            let text = await doc.contents
            guard let text else { return nil }
            return (doc.filename, text)
        }
        return nil
    }
}
