import Foundation
import os

// Prefer the official Codex app-server snapshot written by Btoll's local bridge.
// The legacy web endpoint is used only when it supplies explicit window durations.
struct CodexQuotaClient {
    private static let log = os.Logger(subsystem: "com.atoll.DynamicIsland", category: "CodexQuota")
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let accessToken: String
            let accountId: String?
        }
        let tokens: Tokens
    }

    private struct RateLimitWindow: Decodable {
        let usedPercent: Double
        let resetAt: Double?
        let resetAfterSeconds: Double?
        let windowDurationMins: Int?
    }

    private struct BridgeDashboard: Decodable {
        struct Quota: Decodable { let used: Double; let reset: Double?; let observed: Double }
        let quota: Quota?
    }

    private struct RateLimit: Decodable {
        let primaryWindow: RateLimitWindow?
        let secondaryWindow: RateLimitWindow?
    }

    private struct UsageResponse: Decodable {
        let rateLimit: RateLimit?
    }

    // Never throws: any credential/network/parse failure yields (nil, nil).
    func fetchLimits() async -> (session: UsageLimit?, week: UsageLimit?) {
        if let weekly = bridgeWeeklyLimit() { return (nil, weekly) }
        guard let creds = loadCredentials() else {
            Self.log.notice("no credentials: auth.json/Keychain missing or unparseable")
            return (nil, nil)
        }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Atoll", forHTTPHeaderField: "User-Agent")
        if let accountId = creds.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.log.error("wham/usage HTTP \(code) — \(code == 401 || code == 403 ? "auth/credential" : "request") failure")
                return (nil, nil)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let now = Date()
            if let decoded = try? decoder.decode(UsageResponse.self, from: data) {
                let windows = [decoded.rateLimit?.primaryWindow, decoded.rateLimit?.secondaryWindow].compactMap { $0 }
                let sessionLimit = windows.first { $0.windowDurationMins == 300 }.map { limit(from: $0, now: now) }
                let weekLimit = windows.first { $0.windowDurationMins == 10080 }.map { limit(from: $0, now: now) }
                if sessionLimit != nil || weekLimit != nil { return (sessionLimit, weekLimit) }
            }
            Self.log.error("wham/usage 200 but no identified quota windows (\(data.count) bytes)")
            return (nil, nil)
        } catch {
            Self.log.error("wham/usage request errored: \(error.localizedDescription, privacy: .public)")
            return (nil, nil)
        }
    }

    private func limit(from window: RateLimitWindow, now: Date) -> UsageLimit {
        let resets = window.resetAt.map { Date(timeIntervalSince1970: $0) } ?? window.resetAfterSeconds.map { now.addingTimeInterval($0) }
        return UsageLimit(used: window.usedPercent, limit: 100, resetsAt: resets)
    }

    private func bridgeWeeklyLimit() -> UsageLimit? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AtollCodexBridge/dashboard.json")
        guard let data = try? Data(contentsOf: url),
              let quota = try? JSONDecoder().decode(BridgeDashboard.self, from: data).quota,
              Date().timeIntervalSince1970 * 1000 - quota.observed < 5 * 60 * 1000,
              (0...100).contains(quota.used) else { return nil }
        return UsageLimit(used: quota.used, limit: 100,
                          resetsAt: quota.reset.map { Date(timeIntervalSince1970: $0) })
    }

    // auth.json ($CODEX_HOME, ~/.codex, ~/.config/codex), then Keychain "Codex Auth" holding the same JSON payload.
    private func loadCredentials() -> (accessToken: String, accountId: String?)? {
        for path in authPaths() {
            if let data = try? Data(contentsOf: path), let creds = parseAuth(data) { return creds }
        }
        guard let value = KeychainReader.genericPassword(service: "Codex Auth"),
              let creds = parseAuth(Data(value.utf8)) else { return nil }
        return creds
    }

    private func authPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            return [URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")]
        }
        return [
            home.appendingPathComponent(".codex/auth.json"),
            home.appendingPathComponent(".config/codex/auth.json"),
        ]
    }

    private func parseAuth(_ data: Data) -> (accessToken: String, accountId: String?)? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let parsed = try? decoder.decode(AuthFile.self, from: data) else { return nil }
        return (parsed.tokens.accessToken, parsed.tokens.accountId)
    }
}
