import Testing
import Workspace

// Pure gitignore-matching tests — the Phase 2 analog of MemoryPolicyTests.
// No `import Foundation` here (keeps the fast suite portable).

struct GitignorePatternTests {

    @Test(arguments: [
        // (pattern, path, isDirectory, expectedMatch)
        ("*.log", "a.log", false, true),
        ("*.log", "dir/b.log", false, true),
        ("*.log", "log", false, false),
        ("/build", "build", true, true),
        ("/build", "src/build", true, false),       // anchored, not at root
        ("build/", "build", true, true),
        ("build/", "build", false, false),          // dir-only must not match a file
        ("**/foo", "foo", false, true),
        ("**/foo", "a/b/foo", false, true),
        ("a/**/b", "a/b", false, true),
        ("a/**/b", "a/x/y/b", false, true),
        ("logs/**", "logs/x/y", false, true),
        ("file?.txt", "file1.txt", false, true),
        ("file?.txt", "file10.txt", false, false),  // ? matches exactly one char
        ("a*c", "axc", false, true),
        ("a*c", "a/c", false, false),               // * does not cross '/'
        ("node_modules", "src/node_modules", true, true), // unanchored basename, any depth
    ] as [(String, String, Bool, Bool)])
    func matches(_ testCase: (String, String, Bool, Bool)) {
        let pattern = GitignorePattern(line: testCase.0)
        #expect(pattern != nil, "failed to parse \(testCase.0)")
        #expect(pattern?.matches(relativePath: testCase.1, isDirectory: testCase.2) == testCase.3,
                "\(testCase.0) vs \(testCase.1) (isDir=\(testCase.2))")
    }

    @Test func blanksAndCommentsParseToNil() {
        #expect(GitignorePattern(line: "") == nil)
        #expect(GitignorePattern(line: "    ") == nil)
        #expect(GitignorePattern(line: "# a comment") == nil)
    }

    @Test func escapedHashIsLiteral() {
        let p = GitignorePattern(line: "\\#notacomment")
        #expect(p?.matches(relativePath: "#notacomment", isDirectory: false) == true)
    }
}

struct IgnoreRulesTests {

    @Test func lastMatchWinsWithNegation() {
        let rules = IgnoreRules.parse(["*.log\n!keep.log\n"])
        #expect(rules.lastDecision(pathSegments: ["x.log"], isDirectory: false) == true)
        #expect(rules.lastDecision(pathSegments: ["keep.log"], isDirectory: false) == false)
    }

    @Test func opencodeignoreLayeredAfterGitignore() {
        // Two file contents concatenated in order (.gitignore then .opencodeignore).
        let rules = IgnoreRules.parse(["*.log\n", "!important.log\n"])
        #expect(rules.lastDecision(pathSegments: ["important.log"], isDirectory: false) == false)
        #expect(rules.lastDecision(pathSegments: ["other.log"], isDirectory: false) == true)
    }

    @Test func noMatchReturnsNil() {
        let rules = IgnoreRules.parse(["*.log\n"])
        #expect(rules.lastDecision(pathSegments: ["a.txt"], isDirectory: false) == nil)
    }

    @Test func charClassesAreTreatedLiterally_outOfScope() {
        // 2a does NOT support char-classes; "[ab].log" is matched literally.
        let rules = IgnoreRules.parse(["[ab].log\n"])
        #expect(rules.lastDecision(pathSegments: ["a.log"], isDirectory: false) == nil)
        #expect(rules.lastDecision(pathSegments: ["[ab].log"], isDirectory: false) == true)
    }
}

struct IgnoreStackTests {

    @Test func nestedGitignoreOverridesParent() {
        var stack = IgnoreStack()
        stack.add(.init(baseSegments: [], rules: IgnoreRules.parse(["*.log\n"])))            // root ignores *.log
        stack.add(.init(baseSegments: ["sub"], rules: IgnoreRules.parse(["!keep.log\n"])))   // sub re-includes keep.log

        #expect(stack.isIgnored(pathSegments: ["a.log"], isDirectory: false) == true)
        #expect(stack.isIgnored(pathSegments: ["sub", "a.log"], isDirectory: false) == true)     // root still applies
        #expect(stack.isIgnored(pathSegments: ["sub", "keep.log"], isDirectory: false) == false) // sub overrides
    }

    @Test func scopeNeverIgnoresItsOwnDirectory() {
        var stack = IgnoreStack()
        stack.add(.init(baseSegments: ["sub"], rules: IgnoreRules.parse(["*\n"])))
        #expect(stack.isIgnored(pathSegments: ["sub"], isDirectory: true) == false)
        #expect(stack.isIgnored(pathSegments: ["sub", "x"], isDirectory: false) == true)
    }

    @Test func pruneDropsSiblingScopes() {
        var stack = IgnoreStack()
        stack.add(.init(baseSegments: [], rules: IgnoreRules.parse(["*.tmp\n"])))
        stack.add(.init(baseSegments: ["left"], rules: IgnoreRules.parse(["secret.txt\n"])))
        stack.prune(for: ["right", "secret.txt"])

        #expect(stack.isIgnored(pathSegments: ["right", "secret.txt"], isDirectory: false) == false)
        #expect(stack.isIgnored(pathSegments: ["right", "a.tmp"], isDirectory: false) == true)
    }
}
