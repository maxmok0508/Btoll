import Foundation

struct CodexUsageProvider: UsageProvider {
    let id: ProviderID = .codex
    let quotaClient: CodexQuotaClient

    init(quotaClient: CodexQuotaClient = CodexQuotaClient()) {
        self.quotaClient = quotaClient
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        let quota = await quotaClient.fetchLimits()
        guard quota.session != nil || quota.week != nil else {
            throw UsageError.notConfigured("Codex is not signed in or its quota is unavailable")
        }
        var snapshot = UsageSnapshot()
        snapshot.sessionLimit = quota.session
        snapshot.weekLimit = quota.week
        snapshot.lastUpdated = now
        return snapshot
    }
}
