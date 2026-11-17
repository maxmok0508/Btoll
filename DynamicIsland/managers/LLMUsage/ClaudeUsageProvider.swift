import Foundation

struct ClaudeUsageProvider: UsageProvider {
    let id: ProviderID = .claude
    let quotaClient: ClaudeQuotaClient

    init(quotaClient: ClaudeQuotaClient = ClaudeQuotaClient()) {
        self.quotaClient = quotaClient
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        let quota = await quotaClient.fetchLimits()
        guard quota.session != nil || quota.week != nil else {
            throw UsageError.notConfigured("Claude Code is not signed in or its quota is unavailable")
        }
        var snapshot = UsageSnapshot()
        snapshot.sessionLimit = quota.session
        snapshot.weekLimit = quota.week
        snapshot.lastUpdated = now
        return snapshot
    }
}

enum UsageError: LocalizedError {
    case notFound(String)
    case notConfigured(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let m), .notConfigured(let m): return m
        }
    }
}
