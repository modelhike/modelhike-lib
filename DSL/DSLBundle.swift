// Exists solely so SPM treats this directory as a Swift target and bundles
// the DSL markdown files alongside it. Do not add logic here.
import Foundation
public enum DSLBundle {
    public static let module: Bundle = .module
}
