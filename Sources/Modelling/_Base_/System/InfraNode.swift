//
//  InfraNode.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//
//  An infrastructure element declared inside a system body using a setext header.
//  Used for databases, message brokers, caches, and other infra that don't
//  warrant a full container definition.
//
//  DSL syntax:
//
//      PostgreSQL [database] #primary-db -- Main relational store
//      ++++++++++++++++++++++++++++++++++
//      host    = db.internal
//      port    = 5432
//      version = 14
//
//      Kafka Events [message-broker] #async
//      ++++++++++++++++++++++++++++++++++++
//      bootstrap.servers = kafka:9092
//      group.id          = platform
//

import Foundation

// MARK: - InfraProperty

/// A single `key = value` configuration property on an infra node.
public struct InfraProperty: Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key.trim()
        self.value = value.trim()
    }
}

// MARK: - InfraNode

public struct InfraNode: Sendable {
    /// Normalised (variable-name safe) identifier.
    public let name: String
    /// Original human-readable name as written in the DSL.
    public let givenname: String
    /// Infrastructure category declared in `[...]` after the name, e.g. `database`, `message-broker`.
    public var infraType: String?
    /// Optional description from an inline ` -- text` suffix.
    public var description: String?
    /// Free-form tags, e.g. `#primary-db`, `#async`.
    public var tags: [Tag]
    /// Configuration key-value properties declared on lines below the underline.
    public var properties: [InfraProperty]

    public init(givenname: String, infraType: String? = nil, description: String? = nil, tags: [Tag] = [], properties: [InfraProperty] = []) {
        let trimmed = givenname.trim()
        self.givenname = trimmed
        self.name = trimmed.normalizeForVariableName()
        self.infraType = infraType
        self.description = description
        self.tags = tags
        self.properties = properties
    }
}
