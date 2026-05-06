import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ZaiModelUsageDay: Sendable {
    public let date: Date
    public let tokensUsed: Int64
    public let modelCallCount: Int64
}

public struct ZaiModelUsageResponse: Decodable, Sendable {
    public let code: Int
    public let msg: String?
    public let success: Bool
    public let data: ZaiModelUsageData?

    var isSuccess: Bool { self.success && self.code == 200 }
}

public struct ZaiModelUsageData: Decodable, Sendable {
    public let xTime: [String]
    public let tokensUsage: [Int64]?
    public let modelCallCount: [Int64]?
}

public struct ZaiModelUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.zaiUsage)
    private static let defaultBaseURL = "https://api.z.ai"
    private static let path = "api/monitor/usage/model-usage"
    private static let timeoutSeconds: TimeInterval = 15

    public static func fetchModelUsage(
        apiKey: String,
        region: ZaiAPIRegion = .global,
        environment: [String: String] = ProcessInfo.processInfo.environment) async -> [ZaiModelUsageDay]?
    {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let baseURL = ZaiSettingsReader.apiHost(environment: environment) ?? Self.defaultBaseURL
        guard var components = URLComponents(string: "\(baseURL)/\(Self.path)") else {
            return nil
        }

        let calendar = Calendar.current
        let endTime = Date()
        let startTime = calendar.date(byAdding: .day, value: -30, to: endTime) ?? endTime

        components.queryItems = [
            URLQueryItem(name: "startTime", value: Self.isoDate(startTime)),
            URLQueryItem(name: "endTime", value: Self.isoDate(endTime)),
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.timeoutInterval = Self.timeoutSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let body = String(data: data, encoding: .utf8)?.prefix(500) {
                    Self.log.debug("ZAI model-usage API returned \(status): \(body)")
                }
                return nil
            }
            let result = Self.parseResponse(data)
            Self.log.info("ZAI model-usage fetched: \(result?.count ?? 0) days")
            return result
        } catch {
            Self.log.error("ZAI model-usage fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseResponse(_ data: Data) -> [ZaiModelUsageDay]? {
        guard !data.isEmpty else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ZaiModelUsageResponse.self, from: data)
            guard response.isSuccess, let data = response.data else { return nil }
            return Self.days(from: data)
        } catch {
            Self.log.error("ZAI model-usage parse error: \(error.localizedDescription)")
            return nil
        }
    }

    private static func days(from data: ZaiModelUsageData) -> [ZaiModelUsageDay] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        var days: [ZaiModelUsageDay] = []
        let tokens = data.tokensUsage ?? []
        let calls = data.modelCallCount ?? []

        for (i, dateStr) in data.xTime.enumerated() {
            guard let date = formatter.date(from: dateStr) else { continue }
            days.append(ZaiModelUsageDay(
                date: date,
                tokensUsed: i < tokens.count ? tokens[i] : 0,
                modelCallCount: i < calls.count ? calls[i] : 0))
        }
        return days
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}
