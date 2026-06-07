import Foundation
import Testing
import Core

struct SystemContextRegistryTests {
    @Test func registryOrdersFiltersRemovesAndTruncatesSources() async {
        let registry = SystemContextRegistry(sources: [
            SystemContextSource(id: "late", title: "Late", body: "late", priority: 20),
            SystemContextSource(id: "hidden", title: "Hidden", body: "secret", priority: 0, visibility: .internalOnly),
            SystemContextSource(id: "early", title: "Early", body: "early", priority: 0),
        ])

        #expect(await registry.all().map(\.id) == ["early", "late"])
        #expect(await registry.all(includeInternal: true).map(\.id) == ["early", "hidden", "late"])

        let rendered = await registry.render(maxCharacters: 80)
        #expect(rendered.contains("[Early]"))
        #expect(!rendered.contains("secret"))

        await registry.register(SystemContextSource(id: "extra", title: "Extra", body: String(repeating: "x", count: 80), priority: 10))
        #expect(await registry.render(maxCharacters: 40).contains("[truncated]"))

        await registry.remove(id: "extra")
        #expect(await registry.source(id: "extra") == nil)
    }
}
