import Testing
import Workspace

struct CodeStructureExtractorTests {
    @Test func linksTreeSitterRuntimeAndGrammarPackages() {
        #expect(TreeSitterRuntimeAvailability.swiftRuntimeLinked)
    }

    @Test func extractsSwiftSymbolsCommentsImportsAndReferences() {
        let source = """
        import Foundation

        /// Greets a named user.
        public actor Greeter {
            /* Stores display name tokens. */
            let defaultName: String

            init(defaultName: String) {
                self.defaultName = defaultName
            }

            func greet(name: String) -> String {
                print(name)
                return MessageFormatter.format(name)
            }
        }

        protocol Speaker {}
        enum Mood { case happy }
        struct MessageFormatter {
            static func format(_ value: String) -> String { value }
        }
        class Helper {}
        """

        let structure = SwiftCodeStructureExtractor().extract(from: source, relativePath: "Sources/Greeter.swift")

        #expect(structure.symbols.contains { $0.name == "Greeter" && $0.kind == "type" })
        #expect(structure.symbols.contains { $0.name == "greet" && $0.kind == "function" })
        #expect(structure.symbols.contains { $0.name == "init" && $0.kind == "initializer" })
        #expect(structure.symbols.contains { $0.name == "defaultName" && $0.kind == "property" })
        #expect(structure.symbols.contains { $0.name == "Speaker" && $0.kind == "type" })
        #expect(structure.symbols.contains { $0.name == "Mood" && $0.kind == "type" })
        #expect(structure.symbols.contains { $0.name == "Helper" && $0.kind == "type" })

        #expect(structure.comments.contains { $0.contains("Greets a named user") })
        #expect(structure.comments.contains { $0.contains("Stores display name tokens") })

        #expect(structure.references.contains { $0.name == "Foundation" && $0.kind == "import" })
        #expect(structure.references.contains { $0.name == "print" && $0.kind == "call" })
        #expect(structure.references.contains { $0.name == "MessageFormatter" && $0.kind == "type" })
        #expect(structure.references.contains { $0.name == "name" && $0.kind == "identifier" })
    }

    @Test func ignoresNonSwiftFiles() {
        let structure = SwiftCodeStructureExtractor().extract(from: "func fake() {}", relativePath: "README.md")
        #expect(structure == CodeStructure())
    }

    @Test func invalidSwiftDoesNotThrowOrCrash() {
        let structure = SwiftCodeStructureExtractor().extract(from: "func { /* unfinished", relativePath: "Broken.swift")
        #expect(structure.symbols.isEmpty)
        #expect(structure.comments == ["unfinished"])
    }
}
