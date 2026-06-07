import Foundation

public enum InstructionDiscoveryError: Error, Sendable, Equatable {
    case pathEscapesWorkspace(String)
}

public enum InstructionSourceKind: String, Sendable, Equatable, Codable, CaseIterable {
    case configured
    case agentsFile
}

public struct DiscoveredInstruction: Sendable, Equatable, Codable, Identifiable {
    public var id: String { relativePath }
    public var relativePath: String
    public var kind: InstructionSourceKind
    public var text: String
    public var byteCount: Int
    public var isTruncated: Bool
    public var depth: Int

    public init(
        relativePath: String,
        kind: InstructionSourceKind,
        text: String,
        byteCount: Int,
        isTruncated: Bool,
        depth: Int
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.text = text
        self.byteCount = byteCount
        self.isTruncated = isTruncated
        self.depth = depth
    }
}

public struct InstructionDiscovery: Sendable {
    public var root: URL
    public var instructionFileName: String
    public var maxInstructionBytes: Int

    public init(
        root: URL,
        instructionFileName: String = "AGENTS.md",
        maxInstructionBytes: Int = 32_000
    ) {
        self.root = root.standardizedFileURL
        self.instructionFileName = instructionFileName
        self.maxInstructionBytes = max(0, maxInstructionBytes)
    }

    public func discover(
        for relativePath: String? = nil,
        configuredPaths: [String] = []
    ) throws -> [DiscoveredInstruction] {
        var seen: Set<String> = []
        var instructions: [DiscoveredInstruction] = []

        for configuredPath in configuredPaths {
            guard !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let normalized = try normalizedRelativePath(configuredPath)
            guard seen.insert(normalized).inserted else { continue }
            if let instruction = readInstruction(relativePath: normalized, kind: .configured, depth: -1) {
                instructions.append(instruction)
            }
        }

        let targetDirectory = try targetDirectory(for: relativePath)
        for (depth, directory) in directoriesFromRoot(to: targetDirectory).enumerated() {
            let candidate = directory.appendingPathComponent(instructionFileName, isDirectory: false)
            let normalized = try relativePathForURL(candidate)
            guard seen.insert(normalized).inserted else { continue }
            if let instruction = readInstruction(relativePath: normalized, kind: .agentsFile, depth: depth) {
                instructions.append(instruction)
            }
        }

        return instructions
    }

    private func targetDirectory(for relativePath: String?) throws -> URL {
        guard let relativePath, !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return root
        }
        let normalized = try normalizedRelativePath(relativePath)
        let candidate = root.appendingPathComponent(normalized)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate.standardizedFileURL
        }
        return candidate.deletingLastPathComponent().standardizedFileURL
    }

    private func directoriesFromRoot(to targetDirectory: URL) -> [URL] {
        let rootPath = root.path
        let targetPath = targetDirectory.standardizedFileURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else { return [root] }
        let suffix = targetPath == rootPath ? "" : String(targetPath.dropFirst(rootPath.count + 1))
        var directories = [root]
        var current = root
        for component in suffix.split(separator: "/").map(String.init) {
            current = current.appendingPathComponent(component, isDirectory: true)
            directories.append(current.standardizedFileURL)
        }
        return directories
    }

    private func readInstruction(
        relativePath: String,
        kind: InstructionSourceKind,
        depth: Int
    ) -> DiscoveredInstruction? {
        let url = root.appendingPathComponent(relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let readLimit = maxInstructionBytes + 1
        let data = handle.readData(ofLength: readLimit)
        let isTruncated = data.count > maxInstructionBytes
        let bounded = isTruncated ? data.prefix(maxInstructionBytes) : data[...]
        guard let text = String(data: Data(bounded), encoding: .utf8) else { return nil }
        return DiscoveredInstruction(
            relativePath: relativePath,
            kind: kind,
            text: text,
            byteCount: min(data.count, maxInstructionBytes),
            isTruncated: isTruncated,
            depth: depth)
    }

    private func normalizedRelativePath(_ relativePath: String) throws -> String {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("/") else {
            throw InstructionDiscoveryError.pathEscapesWorkspace(relativePath)
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.contains("..") else {
            throw InstructionDiscoveryError.pathEscapesWorkspace(relativePath)
        }
        let normalized = components.joined(separator: "/")
        let candidate = root.appendingPathComponent(normalized).standardizedFileURL
        _ = try relativePathForURL(candidate)
        return normalized
    }

    private func relativePathForURL(_ url: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let candidate = url.standardizedFileURL
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            throw InstructionDiscoveryError.pathEscapesWorkspace(candidatePath)
        }
        if FileManager.default.fileExists(atPath: candidatePath) {
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
            let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolvedCandidate == resolvedRoot || resolvedCandidate.hasPrefix(resolvedRoot + "/") else {
                throw InstructionDiscoveryError.pathEscapesWorkspace(candidatePath)
            }
        }
        guard candidatePath != rootPath else { return "" }
        return String(candidatePath.dropFirst(rootPath.count + 1))
    }
}
