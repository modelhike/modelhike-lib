//
//  Data.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

extension Data {

    public func toHex() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }

}
