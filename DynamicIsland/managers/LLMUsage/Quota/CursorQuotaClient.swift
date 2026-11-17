import Foundation

// Fetches Cursor's current billing-period usage via the local session token. UNVERIFIED — endpoint per spec, not exercised against a live account.
struct CursorQuotaClient {
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    private struct PlanUsage: Decodable {
        let totalPercentUsed: Double
    }

    private struct UsageResponse: Decodable {
        let planUsage: PlanUsage?
        let billingCycleEnd: Double?
    }

    // The response is for a billing period, which must not be presented as a weekly limit.
    func fetchBillingLimit() async -> UsageLimit? {
        guard let token = CursorTokenStore.accessToken() else { return nil }
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            guard let percent = decoded.planUsage?.totalPercentUsed else { return nil }
            let resets = decoded.billingCycleEnd.map { Date(timeIntervalSince1970: $0 / 1000) }
            return UsageLimit(used: percent, limit: 100, resetsAt: resets)
        } catch {
            return nil
        }
    }
}
