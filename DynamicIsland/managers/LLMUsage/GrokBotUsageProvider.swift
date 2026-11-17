import Foundation

/// Reads only Grok Bot's account-scoped weekly quota cache. Credentials and
/// transcript replicas are never opened. The client controls when this cache
/// refreshes; Btoll displays its observation time instead of claiming live data.
struct GrokBotUsageProvider: UsageProvider {
    let id: ProviderID = .grok
    let root: URL

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence")) {
        self.root = root
    }

    private struct Slot: Decodable {
        let schemaVersion: Int
        let value: String
    }
    private struct Cache: Decodable {
        struct Value: Decodable {
            struct Reading: Decodable {
                struct Usage: Decodable {
                    let percentUsed: Double
                    let nextResetMs: Double?
                    let readForTeamId: Int?
                    let hasNonZeroIncludedLimit: Bool
                }
                let readAtMs: Double
                let usage: Usage
            }
            let kind: String
            let expiresAtMs: Double
            let selectedTeamId: Int?
            let reading: Reading?
        }
        let schemaVersion: Int
        let value: Value
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        let slotURL = root.appendingPathComponent(Self.base32("sand.client.slice.client-meta.account-slot") + ".blob")
        guard let slotData = try? Data(contentsOf: slotURL),
              let slot = try? JSONDecoder().decode(Slot.self, from: slotData),
              slot.schemaVersion == 1,
              !slot.value.isEmpty,
              slot.value.count < 256 else {
            throw UsageError.notConfigured("Grok Bot account cache is unavailable")
        }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let scope = slot.value.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            throw UsageError.notConfigured("Grok Bot account scope is invalid")
        }
        let key = "sand.client.slice.account.\(scope).weekly-usage.cache"
        let cacheURL = root.appendingPathComponent(Self.base32(key) + ".blob")
        guard let cacheData = try? Data(contentsOf: cacheURL),
              cacheData.count < 100_000,
              let cache = try? JSONDecoder().decode(Cache.self, from: cacheData),
              cache.schemaVersion == 2,
              cache.value.kind == "present",
              let reading = cache.value.reading,
              cache.value.selectedTeamId == reading.usage.readForTeamId,
              reading.usage.hasNonZeroIncludedLimit else {
            throw UsageError.notConfigured("Grok Bot weekly quota cache is unavailable")
        }
        let nowMs = now.timeIntervalSince1970 * 1000
        guard cache.value.expiresAtMs > nowMs,
              reading.readAtMs <= nowMs + 5 * 60 * 1000,
              nowMs - reading.readAtMs < 24 * 60 * 60 * 1000,
              reading.usage.percentUsed.isFinite,
              reading.usage.percentUsed >= 0 else {
            throw UsageError.notConfigured("Grok Bot weekly quota cache is stale")
        }
        var snapshot = UsageSnapshot()
        snapshot.weekLimit = UsageLimit(used: reading.usage.percentUsed, limit: 100,
            resetsAt: reading.usage.nextResetMs.map { Date(timeIntervalSince1970: $0 / 1000) })
        snapshot.lastUpdated = Date(timeIntervalSince1970: reading.readAtMs / 1000)
        return snapshot
    }

    static func base32(_ value: String) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in value.utf8 {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 31])
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return output
    }
}
