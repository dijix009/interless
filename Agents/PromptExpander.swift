import Foundation

public enum PromptMentionKind: String, Sendable, Equatable, Codable, CaseIterable {
    case file
    case directory
    case agent
    case reference
}

public struct PromptExpansionMention: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(kind.rawValue):\(target)" }
    public var kind: PromptMentionKind
    public var target: String
    public var rendered: String
    public var isTruncated: Bool

    public init(kind: PromptMentionKind, target: String, rendered: String, isTruncated: Bool = false) {
        self.kind = kind
        self.target = target
        self.rendered = rendered
        self.isTruncated = isTruncated
    }
}

public struct PromptAttachmentRecord: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var path: String
    public var kind: String
    public var byteCount: Int
    public var isTruncated: Bool

    public init(
        id: String = UUID().uuidString,
        path: String,
        kind: String,
        byteCount: Int,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.path = path
        self.kind = kind
        self.byteCount = byteCount
        self.isTruncated = isTruncated
    }
}

public struct PromptExpansion: Sendable, Equatable, Codable {
    public var originalPrompt: String
    public var expandedPrompt: String
    public var renderedContext: String
    public var mentions: [PromptExpansionMention]
    public var attachments: [PromptAttachmentRecord]
    public var diagnostics: [String]
    public var isTruncated: Bool

    public init(
        originalPrompt: String,
        expandedPrompt: String,
        renderedContext: String = "",
        mentions: [PromptExpansionMention] = [],
        attachments: [PromptAttachmentRecord] = [],
        diagnostics: [String] = [],
        isTruncated: Bool = false
    ) {
        self.originalPrompt = originalPrompt
        self.expandedPrompt = expandedPrompt
        self.renderedContext = renderedContext
        self.mentions = mentions
        self.attachments = attachments
        self.diagnostics = diagnostics
        self.isTruncated = isTruncated
    }
}

public struct PromptExpansionOptions: Sendable, Equatable, Codable {
    public var maxMentionCharacters: Int
    public var maxDirectoryEntries: Int
    public var maxAttachmentBytes: Int
    public var maxContextCharacters: Int

    public init(
        maxMentionCharacters: Int = 8_000,
        maxDirectoryEntries: Int = 64,
        maxAttachmentBytes: Int = 1_000_000,
        maxContextCharacters: Int = 24_000
    ) {
        self.maxMentionCharacters = max(0, maxMentionCharacters)
        self.maxDirectoryEntries = max(0, maxDirectoryEntries)
        self.maxAttachmentBytes = max(0, maxAttachmentBytes)
        self.maxContextCharacters = max(0, maxContextCharacters)
    }
}

public struct PromptExpansionResolver: Sendable {
    public var readFile: @Sendable (_ path: String, _ maxCharacters: Int) async throws -> String?
    public var listDirectory: @Sendable (_ path: String, _ limit: Int) async throws -> [String]
    public var resolveAgent: @Sendable (_ id: String) async throws -> String?
    public var resolveReference: @Sendable (_ id: String) async throws -> String?
    public var normalizeAttachment: @Sendable (_ path: String, _ maxBytes: Int) async throws -> PromptAttachmentRecord?

    public init(
        readFile: @escaping @Sendable (_ path: String, _ maxCharacters: Int) async throws -> String? = { _, _ in nil },
        listDirectory: @escaping @Sendable (_ path: String, _ limit: Int) async throws -> [String] = { _, _ in [] },
        resolveAgent: @escaping @Sendable (_ id: String) async throws -> String? = { _ in nil },
        resolveReference: @escaping @Sendable (_ id: String) async throws -> String? = { _ in nil },
        normalizeAttachment: @escaping @Sendable (_ path: String, _ maxBytes: Int) async throws -> PromptAttachmentRecord? = { _, _ in nil }
    ) {
        self.readFile = readFile
        self.listDirectory = listDirectory
        self.resolveAgent = resolveAgent
        self.resolveReference = resolveReference
        self.normalizeAttachment = normalizeAttachment
    }
}

public struct PromptExpander: Sendable {
    public var resolver: PromptExpansionResolver
    public var options: PromptExpansionOptions

    public init(
        resolver: PromptExpansionResolver = PromptExpansionResolver(),
        options: PromptExpansionOptions = PromptExpansionOptions()
    ) {
        self.resolver = resolver
        self.options = options
    }

    public func expand(prompt: String, attachments: [String] = []) async -> PromptExpansion {
        var mentions: [PromptExpansionMention] = []
        var diagnostics: [String] = []
        var sections: [String] = []
        var seen: Set<String> = []

        for reference in mentionReferences(in: prompt) {
            let key = "\(reference.kind.rawValue):\(reference.target)"
            guard seen.insert(key).inserted else { continue }
            do {
                switch reference.kind {
                case .file:
                    guard let text = try await resolver.readFile(reference.target, options.maxMentionCharacters) else {
                        diagnostics.append("Unable to resolve @file:\(reference.target)")
                        continue
                    }
                    let bounded = truncate(text, limit: options.maxMentionCharacters)
                    let mention = PromptExpansionMention(
                        kind: .file,
                        target: reference.target,
                        rendered: bounded.text,
                        isTruncated: bounded.truncated)
                    mentions.append(mention)
                    sections.append(render(mention: mention, title: "File"))
                case .directory:
                    let entries = try await resolver.listDirectory(reference.target, options.maxDirectoryEntries)
                    guard !entries.isEmpty else {
                        diagnostics.append("Unable to resolve @dir:\(reference.target)")
                        continue
                    }
                    let rendered = entries.prefix(options.maxDirectoryEntries).joined(separator: "\n")
                    let mention = PromptExpansionMention(
                        kind: .directory,
                        target: reference.target,
                        rendered: rendered,
                        isTruncated: entries.count > options.maxDirectoryEntries)
                    mentions.append(mention)
                    sections.append(render(mention: mention, title: "Directory"))
                case .agent:
                    guard let text = try await resolver.resolveAgent(reference.target) else {
                        diagnostics.append("Unable to resolve @agent:\(reference.target)")
                        continue
                    }
                    let bounded = truncate(text, limit: options.maxMentionCharacters)
                    let mention = PromptExpansionMention(
                        kind: .agent,
                        target: reference.target,
                        rendered: bounded.text,
                        isTruncated: bounded.truncated)
                    mentions.append(mention)
                    sections.append(render(mention: mention, title: "Agent"))
                case .reference:
                    guard let text = try await resolver.resolveReference(reference.target) else {
                        diagnostics.append("Unable to resolve @reference:\(reference.target)")
                        continue
                    }
                    let bounded = truncate(text, limit: options.maxMentionCharacters)
                    let mention = PromptExpansionMention(
                        kind: .reference,
                        target: reference.target,
                        rendered: bounded.text,
                        isTruncated: bounded.truncated)
                    mentions.append(mention)
                    sections.append(render(mention: mention, title: "Reference"))
                }
            } catch {
                diagnostics.append("Failed to resolve @\(reference.kind.rawValue):\(reference.target): \(error)")
            }
        }

        var normalizedAttachments: [PromptAttachmentRecord] = []
        for attachment in attachments {
            do {
                if let normalized = try await resolver.normalizeAttachment(attachment, options.maxAttachmentBytes) {
                    normalizedAttachments.append(normalized)
                } else {
                    diagnostics.append("Unable to normalize attachment \(attachment)")
                }
            } catch {
                diagnostics.append("Failed to normalize attachment \(attachment): \(error)")
            }
        }
        if !normalizedAttachments.isEmpty {
            let rendered = normalizedAttachments.map { attachment in
                "\(attachment.path) kind=\(attachment.kind) bytes=\(attachment.byteCount)"
            }
            sections.append("Attachments:\n" + rendered.joined(separator: "\n"))
        }

        let combinedContext = sections.joined(separator: "\n\n")
        let boundedContext = truncate(combinedContext, limit: options.maxContextCharacters)
        return PromptExpansion(
            originalPrompt: prompt,
            expandedPrompt: prompt,
            renderedContext: boundedContext.text,
            mentions: mentions,
            attachments: normalizedAttachments,
            diagnostics: diagnostics,
            isTruncated: boundedContext.truncated || mentions.contains(where: \.isTruncated))
    }

    private struct MentionReference {
        var kind: PromptMentionKind
        var target: String
    }

    private func mentionReferences(in prompt: String) -> [MentionReference] {
        prompt
            .split(whereSeparator: \.isWhitespace)
            .compactMap { token -> MentionReference? in
                let cleaned = cleanToken(String(token))
                guard cleaned.hasPrefix("@") else { return nil }
                if let target = target(after: "@file:", in: cleaned) {
                    return MentionReference(kind: .file, target: target)
                }
                if let target = target(after: "@dir:", in: cleaned) {
                    return MentionReference(kind: .directory, target: target)
                }
                if let target = target(after: "@agent:", in: cleaned) {
                    return MentionReference(kind: .agent, target: target)
                }
                if let target = target(after: "@reference:", in: cleaned) {
                    return MentionReference(kind: .reference, target: target)
                }
                let shorthand = String(cleaned.dropFirst())
                guard shorthand.contains("/") || shorthand.contains(".") else { return nil }
                return MentionReference(kind: .file, target: shorthand)
            }
    }

    private func target(after prefix: String, in token: String) -> String? {
        guard token.hasPrefix(prefix) else { return nil }
        let target = String(token.dropFirst(prefix.count))
        return target.isEmpty ? nil : target
    }

    private func cleanToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\r,.;)]}\"'"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "([{<\"'"))
    }

    private func render(mention: PromptExpansionMention, title: String) -> String {
        """
        \(title) @\(mention.kind.rawValue):\(mention.target)
        \(mention.rendered)
        """
    }

    private func truncate(_ text: String, limit: Int) -> (text: String, truncated: Bool) {
        guard text.count > limit else { return (text, false) }
        guard limit > 16 else { return (String(text.prefix(limit)), true) }
        return (String(text.prefix(limit - 16)) + "\n[truncated]\n", true)
    }
}
