#if canImport(SwiftTreeSitter)
@preconcurrency import SwiftTreeSitter
#endif

#if canImport(TreeSitterSwift)
@preconcurrency import TreeSitterSwift
#endif

/// Confirms the Swift tree-sitter runtime and grammar packages are linked into
/// `Workspace`. Extraction stays behind `CodeStructureExtractor`.
public enum TreeSitterRuntimeAvailability {
    public static let swiftRuntimeLinked: Bool = {
        #if canImport(SwiftTreeSitter) && canImport(TreeSitterSwift)
        true
        #else
        false
        #endif
    }()
}
