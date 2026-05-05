import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - API response types

public struct ChutesSubscriptionUsageResponse: Decodable, Sendable {
    public let monthly: ChutesRateBucketResponse
    public let fourHour: ChutesRateBucketResponse

    enum CodingKeys: String, CodingKey {
        case monthly
        case fourHour = "four_hour"
    }
}

public struct ChutesRateBucketResponse: Decodable, Sendable {
    public let usage: Double
    public let cap: Double
}

public struct ChutesUserInfoResponse: Decodable, Sendable {
    public let username: String
    public let balance: Double?

    enum CodingKeys: String, CodingKey {
        case username
        case balance
    }
}

// MARK: - Domain types

public struct ChutesRateBucket: Sendable {
    public let usage: Double
    public let cap: Double

    public init(usage: Double, cap: Double) {
        self.usage = usage
        self.cap = cap
    }

    public var usedPercent: Double {
        guard self.cap > 0 else { return 100 }
        return min(100, max(0, (self.usage / self.cap) * 100))
    }

    public var remaining: Double {
        max(0, self.cap - self.usage)
    }
}

public struct ChutesUserInfo: Sendable {
    public let username: String
    public let balance: Double?

    public init(username: String, balance: Double?) {
        self.username = username
        self.balance = balance
    }
}

public struct ChutesUsageSnapshot: Sendable {
    public let fourHour: ChutesRateBucket
    public let monthly: ChutesRateBucket
    public let user: ChutesUserInfo?
    public let updatedAt: Date

    public init(
        fourHour: ChutesRateBucket,
        monthly: ChutesRateBucket,
        user: ChutesUserInfo?,
        updatedAt: Date)
    {
        self.fourHour = fourHour
        self.monthly = monthly
        self.user = user
        self.updatedAt = updatedAt
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let primary = Self.rateWindow(
            bucket: self.fourHour,
            windowMinutes: 240,
            resetsAt: Self.nextFourHourBoundary(from: self.updatedAt))
        let secondary = Self.rateWindow(
            bucket: self.monthly,
            windowMinutes: 43_200,
            resetsAt: Self.nextMonthStart(from: self.updatedAt))

        let loginMethod = self.user.map { $0.username }

        let identity = ProviderIdentitySnapshot(
            providerID: .chutes,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: loginMethod)

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }

    private static func rateWindow(
        bucket: ChutesRateBucket,
        windowMinutes: Int,
        resetsAt: Date?) -> RateWindow
    {
        let detail: String? = bucket.cap > 0
            ? String(format: "$%.2f / $%.2f", bucket.usage, bucket.cap)
            : nil
        return RateWindow(
            usedPercent: bucket.usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt,
            resetDescription: detail)
    }

    /// Next 4-hour boundary aligned to UTC midnight (0:00, 4:00, 8:00, ...).
    static func nextFourHourBoundary(from date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let hour = components.hour ?? 0
        let nextBoundaryHour = ((hour / 4) + 1) * 4
        if nextBoundaryHour >= 24 {
            components.hour = 0
            components.minute = 0
            components.second = 0
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.date(from: components)!) else {
                return date.addingTimeInterval(4 * 3600)
            }
            return tomorrow
        }
        components.hour = nextBoundaryHour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? date.addingTimeInterval(4 * 3600)
    }

    /// First day of next month at 00:00 UTC.
    static func nextMonthStart(from date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        var nextMonth = DateComponents()
        nextMonth.year = components.year
        nextMonth.month = (components.month ?? 1) + 1
        nextMonth.day = 1
        nextMonth.hour = 0
        nextMonth.minute = 0
        nextMonth.second = 0
        nextMonth.timeZone = TimeZone(identifier: "UTC")
        if let result = calendar.date(from: nextMonth) {
            return result
        }
        return date.addingTimeInterval(30 * 24 * 3600)
    }
}

// MARK: - Errors

public enum ChutesUsageError: LocalizedError, Sendable {
    case missingCredentials
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Missing Chutes API key."
        case let .networkError(message):
            "Chutes network error: \(message)"
        case let .apiError(message):
            "Chutes API error: \(message)"
        case let .parseFailed(message):
            "Failed to parse Chutes response: \(message)"
        }
    }
}

// MARK: - Fetcher

public struct ChutesUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.chutesUsage)
    private static let defaultBaseURL = "https://api.chutes.ai"
    private static let timeoutSeconds: TimeInterval = 15

    public static func fetchUsage(
        apiKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> ChutesUsageSnapshot
    {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChutesUsageError.missingCredentials
        }

        let baseURL = ChutesSettingsReader.apiHost(environment: environment) ?? Self.defaultBaseURL

        async let usageTask = Self.fetchSubscriptionUsage(apiKey: apiKey, baseURL: baseURL)
        async let userTask = Self.fetchUserInfo(apiKey: apiKey, baseURL: baseURL)

        let usage = try await usageTask
        let user = await userTask

        return ChutesUsageSnapshot(
            fourHour: ChutesRateBucket(usage: usage.fourHour.usage, cap: usage.fourHour.cap),
            monthly: ChutesRateBucket(usage: usage.monthly.usage, cap: usage.monthly.cap),
            user: user,
            updatedAt: Date())
    }

    private static func fetchSubscriptionUsage(
        apiKey: String,
        baseURL: String) async throws -> ChutesSubscriptionUsageResponse
    {
        guard let url = URL(string: "\(baseURL)/users/me/subscription_usage") else {
            throw ChutesUsageError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChutesUsageError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            Self.log.error("Chutes subscription_usage API returned \(httpResponse.statusCode): \(body)")
            throw ChutesUsageError.apiError("HTTP \(httpResponse.statusCode)")
        }

        if let jsonString = String(data: data, encoding: .utf8) {
            Self.log.debug("Chutes subscription_usage response: \(jsonString)")
        }

        do {
            return try JSONDecoder().decode(ChutesSubscriptionUsageResponse.self, from: data)
        } catch {
            throw ChutesUsageError.parseFailed(error.localizedDescription)
        }
    }

    private static func fetchUserInfo(
        apiKey: String,
        baseURL: String) async -> ChutesUserInfo?
    {
        guard let url = URL(string: "\(baseURL)/users/me") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.timeoutSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(ChutesUserInfoResponse.self, from: data)
            return ChutesUserInfo(username: decoded.username, balance: decoded.balance)
        } catch {
            Self.log.error("Chutes user info fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func _parseSubscriptionUsageForTesting(_ data: Data) throws -> ChutesSubscriptionUsageResponse {
        try JSONDecoder().decode(ChutesSubscriptionUsageResponse.self, from: data)
    }
}
