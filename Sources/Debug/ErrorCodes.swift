//
//  ErrorCodes.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

/// Implemented by error types that expose a stable, documented ModelHike error code.
public protocol ErrorCodeProviding: Sendable {
    var errorCode: String { get }
}

/// Central helpers for looking up and formatting ModelHike error codes.
public enum ErrorCodes {
    /// Returns the stable ModelHike error code for the provided error, if one exists.
    public static func code(for error: any Error) -> String? {
        (error as? any ErrorCodeProviding)?.errorCode
    }

    /// Prefixes a user-facing message with its error code when one is available.
    public static func format(message: String, code: String?) -> String {
        guard let code else { return message }
        return "[\(code)] \(message)"
    }
}

public extension ErrorWithMessage {
    /// Stable documented code for this error, when the underlying type participates
    /// in the ModelHike error-code registry.
    var code: String? {
        ErrorCodes.code(for: self)
    }

    /// User-facing message prefixed with the stable code when one exists.
    var infoWithCode: String {
        ErrorCodes.format(message: info, code: code)
    }
}
