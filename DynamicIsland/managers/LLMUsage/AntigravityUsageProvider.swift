import Foundation

/// Reads the signed-in Antigravity CLI's own `/usage` command. This command
/// reports separate Gemini and Claude/GPT model pools and does not create an
/// agent turn. Only the Gemini pool is shown. No Google credentials or
/// conversation content enter Btoll.
struct AntigravityUsageProvider: UsageProvider {
    let id: ProviderID = .antigravity

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        let output = try await Task.detached(priority: .utility) { try Self.readUsage() }.value
        var snapshot = UsageSnapshot()
        snapshot.lastUpdated = now
        let formatter = ISO8601DateFormatter()
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4,
                  fields[0] == "Gemini Models",
                  fields[1] == "Weekly Limit Remaining",
                  let remaining = Double(fields[2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")),
                  (0...100).contains(remaining) else { continue }
            let reset = formatter.date(from: String(fields[3]))
            snapshot.weekLimit = UsageLimit(used: 100 - remaining, limit: 100, resetsAt: reset)
            break
        }
        guard snapshot.weekLimit != nil else {
            throw UsageError.notConfigured("Antigravity weekly limits are unavailable; sign in to the official CLI")
        }
        return snapshot
    }

    private struct CLIResult: Decodable { let response: String }

    private static func readUsage() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            home.appendingPathComponent("Library/Application Support/AtollCodexBridge/agy"),
            home.appendingPathComponent(".local/bin/agy"),
            URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
            URL(fileURLWithPath: "/usr/local/bin/agy")
        ]
        guard let executable = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw UsageError.notConfigured("Install the official Antigravity CLI to read weekly limits")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-p", "/usage", "--output-format", "json"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 30) == .success else {
            process.terminate()
            throw UsageError.notConfigured("Antigravity quota request timed out")
        }
        guard process.terminationStatus == 0 else {
            throw UsageError.notConfigured("Antigravity CLI is not signed in or quota is unavailable")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard data.count <= 1_000_000,
              let decoded = try? JSONDecoder().decode(CLIResult.self, from: data) else {
            throw UsageError.notConfigured("Antigravity quota response changed")
        }
        return decoded.response
    }
}
