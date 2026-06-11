import Foundation
import Testing
import Shared
@testable import Agents

/// Deterministic counter: ~1 token per 4 characters, matching the engine's
/// fallback estimate closely enough for budget math.
private func fakeCount(_ text: String) async -> Int {
    max(1, text.count / 4)
}

private func message(_ role: GenerationRequest.ChatMessage.Role, _ content: String) -> GenerationRequest.ChatMessage {
    .init(role: role, content: content)
}

struct ContextFitterTests {

    @Test func underBudgetIsUntouched() async {
        let messages = [
            message(.system, "system prompt"),
            message(.user, "hello"),
        ]
        let fit = await AgentContextFitter.fit(
            messages, tokenBudget: 8_192, maxTokens: 512, toolCount: 0, count: fakeCount)
        #expect(fit.messages == messages)
        #expect(fit.degraded == 0)
        #expect(fit.dropped == 0)
    }

    @Test func oversizedToolOutputDegradesBeforeProseDrops() async {
        let bigTool = String(repeating: "x", count: 8_000) // ~2000 tokens
        let messages = [
            message(.system, "system prompt"),
            message(.tool, bigTool),
            message(.assistant, "short answer"),
            message(.user, "latest request"),
        ]
        // Budget chosen so degrading the tool output alone fits.
        let fit = await AgentContextFitter.fit(
            messages, tokenBudget: 2_000, maxTokens: 256, toolCount: 0, count: fakeCount)
        #expect(fit.degraded == 1)
        #expect(fit.dropped == 0)
        #expect(fit.messages.count == 4)
        #expect(fit.messages[1].content.contains("[tool output truncated"))
        // Pins untouched.
        #expect(fit.messages[0].content == "system prompt")
        #expect(fit.messages[3].content == "latest request")
    }

    @Test func dropsOldestButPinsSystemAndLatestUser() async {
        let filler = String(repeating: "y", count: 4_000) // ~1000 tokens each
        let messages = [
            message(.system, "system prompt"),
            message(.user, "old question \(filler)"),
            message(.assistant, filler),
            message(.assistant, filler),
            message(.user, "latest request"),
        ]
        // Tiny budget: only pins + maybe newest fit.
        let fit = await AgentContextFitter.fit(
            messages, tokenBudget: 1_200, maxTokens: 256, toolCount: 0, count: fakeCount)
        #expect(fit.dropped >= 2)
        #expect(fit.messages.first?.role == .system)
        #expect(fit.messages.last?.content == "latest request")
    }

    @Test func nilBudgetDisablesFitting() async {
        let messages = [message(.user, String(repeating: "z", count: 100_000))]
        let fit = await AgentContextFitter.fit(
            messages, tokenBudget: nil, maxTokens: nil, toolCount: 0, count: fakeCount)
        #expect(fit.messages == messages)
    }
}
