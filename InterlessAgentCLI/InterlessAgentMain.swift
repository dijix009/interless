import Foundation
import AgentCLI

@main
struct InterlessAgentMain {
    static func main() async {
        let exitCode = await AgentCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
        if exitCode != 0 {
            Foundation.exit(exitCode)
        }
    }
}
