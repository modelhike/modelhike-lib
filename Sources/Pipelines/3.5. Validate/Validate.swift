//
//  Validate.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public enum Validate {
    /// Semantic validation of the loaded and hydrated model (type refs, mixins, duplicates, etc.).
    public static func models() -> LoadingPass {
        ValidateModelsPass()
    }
}
