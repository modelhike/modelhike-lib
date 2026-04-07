//
//  ModelHikeDSLSchema.swift
//  ModelHike
//
//  Provides the content of the three canonical DSL markdown files as a single
//  value. The files are the single source of truth — this type only reads them.
//  Canonical location: `DSL/` at the repo root (a separate `ModelHikeDSL` SPM
//  target that bundles the markdown files; `ModelHike` depends on it).
//

import Foundation
import ModelHikeDSL

// MARK: - Root

/// The content of the three canonical ModelHike DSL markdown files.
///
/// Use ``bundled`` to load from the package resource bundle (works in all SPM
/// contexts — development, CI, and when consumed as a dependency). Returns
/// `nil` only if the bundle is somehow missing the resource files.
public struct ModelHikeDSLSchema: Sendable, Equatable {

    /// Full content of `DSL/modelHike.dsl.md` — the main DSL grammar guide.
    public let modelHikeDSL: String

    /// Full content of `DSL/codelogic.dsl.md` — fenced method-body logic syntax.
    public let codeLogicDSL: String

    /// Full content of `DSL/templatesoup.dsl.md` — TemplateSoup + SoupyScript syntax.
    public let templateSoupDSL: String
}

// MARK: - Loading

extension ModelHikeDSLSchema {

    /// Loads all three DSL files from the `ModelHikeDSL` resource bundle.
    ///
    /// The `DSL/` folder at the repo root is its own SPM target (`ModelHikeDSL`)
    /// whose only job is to bundle the markdown files. `ModelHike` depends on
    /// it, so the bundle is always present regardless of platform or build
    /// configuration.
    ///
    /// Returns `nil` when a resource URL cannot be resolved or a file cannot
    /// be read (should not happen in a correctly built package).
    public static var bundled: ModelHikeDSLSchema? {
        let bundle = DSLBundle.module
        guard
            let modelHikeURL    = bundle.url(forResource: "modelHike.dsl",    withExtension: "md"),
            let codeLogicURL    = bundle.url(forResource: "codelogic.dsl",    withExtension: "md"),
            let templateSoupURL = bundle.url(forResource: "templatesoup.dsl", withExtension: "md"),
            let modelHike    = try? String(contentsOf: modelHikeURL,    encoding: .utf8),
            let codeLogic    = try? String(contentsOf: codeLogicURL,    encoding: .utf8),
            let templateSoup = try? String(contentsOf: templateSoupURL, encoding: .utf8)
        else { return nil }

        return ModelHikeDSLSchema(
            modelHikeDSL:    modelHike,
            codeLogicDSL:    codeLogic,
            templateSoupDSL: templateSoup
        )
    }
}
