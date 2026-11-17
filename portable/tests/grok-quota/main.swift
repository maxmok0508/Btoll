import Foundation

enum ProviderID { case grok }
protocol UsageProvider {
    var id: ProviderID { get }
    func fetchSnapshot(now: Date) async throws -> UsageSnapshot
}
struct UsageLimit {
    let used: Double
    let limit: Double
    var resetsAt: Date? = nil
}
struct UsageSnapshot {
    var weekLimit: UsageLimit?
    var lastUpdated: Date = .distantPast
}
enum UsageError: Error { case notConfigured(String) }

@main
struct GrokQuotaTest {
    static func main() async throws {
        precondition(GrokBotUsageProvider.base32("foo") == "mzxw6")
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let nowMs = now.timeIntervalSince1970 * 1000
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let slotURL = root.appendingPathComponent(GrokBotUsageProvider.base32("sand.client.slice.client-meta.account-slot") + ".blob")
        let cacheKey = "sand.client.slice.account.auth0%7Cuser_abc.weekly-usage.cache"
        let cacheURL = root.appendingPathComponent(GrokBotUsageProvider.base32(cacheKey) + ".blob")
        try write(["schemaVersion": 1, "value": "auth0|user_abc"], to: slotURL)
        func cache(expiry: Double, readAt: Double, selectedTeam: Int? = nil, readForTeam: Int? = nil) -> [String: Any] {
            return ["schemaVersion": 2, "value": [
                "kind": "present", "expiresAtMs": expiry,
                "selectedTeamId": selectedTeam as Any? ?? NSNull(),
                "reading": ["readAtMs": readAt, "usage": [
                    "percentUsed": 11.5, "nextResetMs": nowMs + 3_600_000,
                    "readForTeamId": readForTeam as Any? ?? NSNull(),
                    "hasNonZeroIncludedLimit": true
                ]]
            ]]
        }
        let provider = GrokBotUsageProvider(root: root)
        try write(cache(expiry: nowMs + 3_600_000, readAt: nowMs - 120_000), to: cacheURL)
        let fresh = try await provider.fetchSnapshot(now: now)
        precondition(fresh.weekLimit?.used == 11.5)
        precondition(fresh.lastUpdated == Date(timeIntervalSince1970: (nowMs - 120_000) / 1000))

        try write(cache(expiry: nowMs - 1, readAt: nowMs - 120_000), to: cacheURL)
        await expectUnavailable(provider, now: now)
        try write(cache(expiry: nowMs + 3_600_000, readAt: nowMs - 120_000,
                        selectedTeam: 1, readForTeam: 2), to: cacheURL)
        await expectUnavailable(provider, now: now)
        try write(cache(expiry: nowMs + 3_600_000, readAt: nowMs - 25 * 3_600_000), to: cacheURL)
        await expectUnavailable(provider, now: now)
        try write(["schemaVersion": 1, "value": "auth0|user_other"], to: slotURL)
        await expectUnavailable(provider, now: now)
        print("Grok Bot quota cache: current account, expiry, team and age checks passed")
    }

    static func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value).write(to: url, options: .atomic)
    }

    static func expectUnavailable(_ provider: GrokBotUsageProvider, now: Date) async {
        do {
            _ = try await provider.fetchSnapshot(now: now)
            fatalError("unexpected quota from stale or mismatched cache")
        } catch { }
    }
}
