import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A single subscription entry from the z.ai API
public struct ZaiSubscriptionEntry: Sendable {
    public let productName: String
    public let status: String
    public let billingCycle: String?
    public let nextRenewTime: String?
    public let autoRenew: Bool
    public let validFrom: String?
    public let validTo: String?

    public var isActive: Bool {
        self.status == "VALID"
    }
}

/// Fetches subscription info from the z.ai business API
public struct ZaiSubscriptionFetcher: Sendable {
    private static let log = CodexBarLog.logger("zai-subscription")
    private static let subscriptionPath = "api/biz/subscription/list"

    public static func fetchSubscription(
        apiKey: String,
        region: ZaiAPIRegion = .global,
        environment: [String: String] = ProcessInfo.processInfo.environment) async -> ZaiSubscriptionEntry?
    {
        guard !apiKey.isEmpty else { return nil }

        let baseURL = Self.resolveBaseURL(region: region, environment: environment)
        guard let url = URL(string: baseURL)?.appendingPathComponent(Self.subscriptionPath) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return Self.parseSubscription(from: data)
        } catch {
            Self.log.debug("z.ai subscription fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func parseSubscription(from data: Data) -> ZaiSubscriptionEntry? {
        guard !data.isEmpty else { return nil }

        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(ZaiSubscriptionListResponse.self, from: data)
            guard response.isSuccess, let entries = response.data else { return nil }

            // Return the first active subscription.
            let active = entries.first { $0.status == "VALID" } ?? entries.first
            return active?.toEntry()
        } catch {
            Self.log.debug("z.ai subscription parse error: \(error.localizedDescription)")
            return nil
        }
    }

    private static func resolveBaseURL(
        region: ZaiAPIRegion,
        environment: [String: String]) -> String
    {
        if let host = ZaiSettingsReader.apiHost(environment: environment) {
            if host.hasPrefix("http") { return host }
            return "https://\(host)"
        }
        return region.baseURLString
    }
}

// MARK: - Response Models

private struct ZaiSubscriptionListResponse: Decodable {
    let code: Int
    let msg: String?
    let data: [ZaiSubscriptionRaw]?
    let success: Bool

    var isSuccess: Bool {
        self.success && self.code == 200
    }
}

private struct ZaiSubscriptionRaw: Decodable {
    let productName: String?
    let status: String?
    let billingCycle: String?
    let nextRenewTime: String?
    let autoRenew: Int?
    let valid: String?

    func toEntry() -> ZaiSubscriptionEntry? {
        guard let name = self.productName, !name.isEmpty else { return nil }

        var validFrom: String?
        var validTo: String?
        if let valid = self.valid {
            // Format: "2026-03-24 01:41:28-2026-06-24 01:41:28"
            // Split on the "-" between two datetime patterns (digits after space+colon+digits).
            let pattern = #"(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s*-\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})"#
            if let match = try? NSRegularExpression(pattern: pattern)
                .firstMatch(in: valid, range: NSRange(valid.startIndex..., in: valid))
            {
                if let r1 = Range(match.range(at: 1), in: valid) { validFrom = String(valid[r1]) }
                if let r2 = Range(match.range(at: 2), in: valid) { validTo = String(valid[r2]) }
            }
        }

        return ZaiSubscriptionEntry(
            productName: name,
            status: self.status ?? "UNKNOWN",
            billingCycle: self.billingCycle,
            nextRenewTime: self.nextRenewTime,
            autoRenew: (self.autoRenew ?? 0) == 1,
            validFrom: validFrom,
            validTo: validTo)
    }
}
