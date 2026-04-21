//
//  ErrorCodes.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum DiagnosticErrorCode: String, Codable, Sendable, CaseIterable {
    case e101 = "E101"
    case e201 = "E201"
    case e202 = "E202"
    case e203 = "E203"
    case e204 = "E204"
    case e205 = "E205"
    case e206 = "E206"
    case e207 = "E207"
    case e208 = "E208"
    case e209 = "E209"
    case e210 = "E210"
    case e211 = "E211"
    case e212 = "E212"
    case e213 = "E213"
    case e214 = "E214"
    case e215 = "E215"
    case e216 = "E216"
    case e217 = "E217"
    case e218 = "E218"
    case e219 = "E219"
    case e301 = "E301"
    case e302 = "E302"
    case e303 = "E303"
    case e304 = "E304"
    case e305 = "E305"
    case e306 = "E306"
    case e307 = "E307"
    case e308 = "E308"
    case e309 = "E309"
    case e310 = "E310"
    case e311 = "E311"
    case e401 = "E401"
    case e402 = "E402"
    case e403 = "E403"
    case e404 = "E404"
    case e405 = "E405"
    case e501 = "E501"
    case e502 = "E502"
    case e503 = "E503"
    case e504 = "E504"
    case e505 = "E505"
    case e506 = "E506"
    case e507 = "E507"
    case e508 = "E508"
    case e509 = "E509"
    case e601 = "E601"
    case e602 = "E602"
    case e603 = "E603"
    case e604 = "E604"
    case e605 = "E605"
    case e606 = "E606"
    case e607 = "E607"
    case e608 = "E608"
    case e609 = "E609"
    case e610 = "E610"
    case e611 = "E611"
    case e612 = "E612"
    case e613 = "E613"
    case e614 = "E614"
    case e615 = "E615"
    case e616 = "E616"
    case e617 = "E617"
    case e618 = "E618"
    case e619 = "E619"
    case e620 = "E620"
    case e621 = "E621"
    case e701 = "E701"
    case e702 = "E702"
    case w201 = "W201"
    case w202 = "W202"
    case w301 = "W301"
    case w302 = "W302"
    case w303 = "W303"
    case w304 = "W304"
    case w305 = "W305"
    case w306 = "W306"
    case w307 = "W307"
    case w620 = "W620"
    case w621 = "W621"
}

/// Implemented by error types that expose a stable, documented ModelHike error code.
public protocol ErrorCodeProviding: Sendable {
    var diagnosticErrorCode: DiagnosticErrorCode { get }
}

/// Central helpers for looking up and formatting ModelHike error codes.
public enum ErrorCodes {
    /// Returns the stable ModelHike error code for the provided error, if one exists.
    public static func code(for error: any Error) -> DiagnosticErrorCode? {
        (error as? any ErrorCodeProviding)?.diagnosticErrorCode
    }

    /// Prefixes a user-facing message with its error code when one is available.
    public static func format(message: String, code: DiagnosticErrorCode?) -> String {
        guard let code else { return message }
        return "[\(code.rawValue)] \(message)"
    }
}

public extension ErrorWithMessage {
    /// Stable documented code for this error, when the underlying type participates
    /// in the ModelHike error-code registry.
    var diagnosticErrorCode: DiagnosticErrorCode? {
        ErrorCodes.code(for: self)
    }

    /// Stable documented code for this error, when the underlying type participates
    /// in the ModelHike error-code registry.
    var code: String? {
        diagnosticErrorCode?.rawValue
    }

    /// User-facing message prefixed with the stable code when one exists.
    var infoWithCode: String {
        ErrorCodes.format(message: info, code: diagnosticErrorCode)
    }
}
