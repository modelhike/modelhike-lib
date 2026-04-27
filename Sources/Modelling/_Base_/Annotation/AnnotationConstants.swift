//
//  AnnotationConstants.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum AnnotationConstants {
    public static let listApi = "list-api"
    public static let apisToGenerate = "apis"
    public static let dontGenerateApis = "no-apis"

    public static let entityAnnotations: Set<String> = [
        "display",
        "index",
        "pagination",
        "roles",
        "schedule",
        "sort"
    ]

    public static let apiAnnotations: Set<String> = [
        apisToGenerate
    ]

    public static let flowAnnotations: Set<String> = [
        "delegate",
        "escalate",
        "params",
        "sla",
        "timeout",
        "trigger"
    ]

    public static let rulesAnnotations: Set<String> = [
        "hit",
        "input",
        "output",
        "score",
        "source"
    ]

    public static let printableAnnotations: Set<String> = [
        "locale",
        "output",
        "page"
    ]

    public static let uiAnnotations: Set<String> = [
        "route",
        "roles",
        "title"
    ]

    public static let agentAnnotations: Set<String> = [
        "auth",
        "capabilities",
        "condition",
        "fallback",
        "max-turns",
        "model",
        "output",
        "requires",
        "script",
        "skill-file",
        "temperature",
        "url"
    ]

    public static let importSectionAnnotations: Set<String> = [
        "column-mapping",
        "format",
        "max-rows",
        "on-duplicate",
        "on-error",
        "preview"
    ]

    public static let exportSectionAnnotations: Set<String> = [
        "columns",
        "filename",
        "format",
        "max-rows"
    ]

    public static let cacheSectionAnnotations: Set<String> = [
        "eviction",
        "exclude-when",
        "invalidate-on",
        "max-entries",
        "strategy",
        "ttl",
        "warm-on"
    ]

    public static let rateLimitSectionAnnotations: Set<String> = [
        "burst",
        "default",
        "headers",
        "overrides",
        "response",
        "tiers"
    ]

    public static let searchSectionAnnotations: Set<String> = [
        "engine",
        "fields",
        "suggestions",
        "sync",
        "synonyms"
    ]

    public static let mediaSectionAnnotations: Set<String> = [
        "accept",
        "deduplicate",
        "field",
        "max-size",
        "metadata",
        "scan",
        "storage",
        "variants"
    ]

    public static let hierarchySectionAnnotations: Set<String> = [
        "children",
        "cycle-detection",
        "max-depth",
        "parent"
    ]

    public static let fixturesSectionAnnotations: Set<String> = [
        "generators",
        "seed"
    ]

    public static let analyticsSectionAnnotations: Set<String> = [
        "destinations",
        "events",
        "funnels",
        "governance",
        "metrics"
    ]

    public static let errorPolicySectionAnnotations: Set<String> = [
        "applies-to"
    ]

    public static let versionedSectionAnnotations: Set<String> = [
        "auto-archive",
        "diff",
        "max-versions",
        "strategy"
    ]

    public static let localizationAnnotations: Set<String> = [
        "fallback",
        "locales"
    ]

    public static let versioningAnnotations: Set<String> = [
        "api-version"
    ]

    public static let valueAnnotations: Set<String> = [
        entityAnnotations,
        apiAnnotations,
        flowAnnotations,
        rulesAnnotations,
        printableAnnotations,
        uiAnnotations,
        agentAnnotations,
        importSectionAnnotations,
        exportSectionAnnotations,
        cacheSectionAnnotations,
        rateLimitSectionAnnotations,
        searchSectionAnnotations,
        mediaSectionAnnotations,
        hierarchySectionAnnotations,
        fixturesSectionAnnotations,
        analyticsSectionAnnotations,
        errorPolicySectionAnnotations,
        versionedSectionAnnotations,
        localizationAnnotations,
        versioningAnnotations
    ].reduce(into: []) { aggregate, annotations in
        aggregate.formUnion(annotations)
    }
}
