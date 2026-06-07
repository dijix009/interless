import Testing
import Shared
import MLXEngine

struct CancellationTests {

    /// Cancelling the task that consumes the stream must stop generation and
    /// release the backend producer (ARCHITECTURE.md §7 "cancellation-safe").
    @Test(.timeLimit(.minutes(1)))
    func cancellingConsumerStopsGeneration() async throws {
        let fake = FakeBackend()
        await fake.setScriptedTokens(Array(repeating: "tok", count: 1000))
        await fake.setPerTokenDelay(.milliseconds(5))
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)

        // Consume the stream in a child task we can cancel.
        let consumer = Task { () -> Int in
            var count = 0
            let stream = await controller.generate(request: .prompt("hi", role: .utility))
            for try await chunk in stream where !chunk.isFinal { count += 1 }
            return count
        }

        // Let a few tokens flow, then cancel mid-stream.
        try await Task.sleep(for: .milliseconds(60))
        consumer.cancel()
        _ = try? await consumer.value

        // Cancellation propagates controller → backend producer.
        var cancelled = false
        for _ in 0..<150 {
            if await fake.generationCancelled { cancelled = true; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(cancelled)
    }
}
