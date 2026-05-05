import Foundation
import Testing
@testable import CodexBarCore

struct ChutesUsageFetcherTests {
    @Test
    func `parses subscription usage response`() throws {
        let json = """
        {
          "monthly": { "usage": 12.50, "cap": 50.00 },
          "four_hour": { "usage": 1.25, "cap": 10.00 }
        }
        """
        let parsed = try ChutesUsageFetcher._parseSubscriptionUsageForTesting(Data(json.utf8))
        #expect(parsed.monthly.usage == 12.50)
        #expect(parsed.monthly.cap == 50.00)
        #expect(parsed.fourHour.usage == 1.25)
        #expect(parsed.fourHour.cap == 10.00)
    }

    @Test
    func `maps to usage snapshot with two windows`() throws {
        let snapshot = ChutesUsageSnapshot(
            fourHour: ChutesRateBucket(usage: 2.0, cap: 10.0),
            monthly: ChutesRateBucket(usage: 15.0, cap: 50.0),
            user: ChutesUserInfo(username: "testuser", balance: 35.0),
            updatedAt: Date())
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary != nil)
        #expect(usage.secondary != nil)
        #expect(usage.primary?.windowMinutes == 240)
        #expect(usage.secondary?.windowMinutes == 43_200)
        #expect(abs((usage.primary?.usedPercent ?? 0) - 20.0) < 0.01)
        #expect(abs((usage.secondary?.usedPercent ?? 0) - 30.0) < 0.01)
        #expect(usage.identity?.loginMethod == "testuser")
    }

    @Test
    func `primary shows 4h rate window detail`() throws {
        let snapshot = ChutesUsageSnapshot(
            fourHour: ChutesRateBucket(usage: 3.45, cap: 10.0),
            monthly: ChutesRateBucket(usage: 25.0, cap: 50.0),
            user: nil,
            updatedAt: Date())
        let usage = snapshot.toUsageSnapshot()
        let detail = usage.primary?.resetDescription ?? ""
        #expect(detail.contains("$3.45"))
        #expect(detail.contains("$10.00"))
    }

    @Test
    func `100 percent when cap is zero`() throws {
        let bucket = ChutesRateBucket(usage: 0, cap: 0)
        #expect(bucket.usedPercent == 100)
    }

    @Test
    func `rate bucket remaining calculation`() throws {
        let bucket = ChutesRateBucket(usage: 3.50, cap: 10.0)
        #expect(bucket.remaining == 6.50)
    }

    @Test
    func `next four hour boundary advances correctly`() {
        // 2025-06-15 10:30 UTC -> next boundary should be 12:00 UTC
        var components = DateComponents()
        components.year = 2025
        components.month = 6
        components.day = 15
        components.hour = 10
        components.minute = 30
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let boundary = ChutesUsageSnapshot.nextFourHourBoundary(from: date)
        let boundaryComponents = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: boundary)
        #expect(boundaryComponents.hour == 12)
        #expect(boundaryComponents.minute == 0)
    }

    @Test
    func `next four hour boundary wraps to next day`() {
        // 2025-06-15 22:00 UTC -> next boundary should be 2025-06-16 00:00 UTC
        var components = DateComponents()
        components.year = 2025
        components.month = 6
        components.day = 15
        components.hour = 22
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let boundary = ChutesUsageSnapshot.nextFourHourBoundary(from: date)
        let boundaryComponents = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: boundary)
        #expect(boundaryComponents.day == 16)
        #expect(boundaryComponents.hour == 0)
    }

    @Test
    func `next month start is first of next month`() {
        // 2025-06-15 -> 2025-07-01 00:00 UTC
        var components = DateComponents()
        components.year = 2025
        components.month = 6
        components.day = 15
        components.hour = 14
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let boundary = ChutesUsageSnapshot.nextMonthStart(from: date)
        let boundaryComponents = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: boundary)
        #expect(boundaryComponents.year == 2025)
        #expect(boundaryComponents.month == 7)
        #expect(boundaryComponents.day == 1)
        #expect(boundaryComponents.hour == 0)
    }

    @Test
    func `next month start wraps year`() {
        // 2025-12-31 -> 2026-01-01 00:00 UTC
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 31
        components.hour = 23
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let boundary = ChutesUsageSnapshot.nextMonthStart(from: date)
        let boundaryComponents = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: boundary)
        #expect(boundaryComponents.year == 2026)
        #expect(boundaryComponents.month == 1)
        #expect(boundaryComponents.day == 1)
    }

    @Test
    func `synthesized resetsAt is non-nil for both windows`() throws {
        let snapshot = ChutesUsageSnapshot(
            fourHour: ChutesRateBucket(usage: 1.0, cap: 10.0),
            monthly: ChutesRateBucket(usage: 5.0, cap: 50.0),
            user: nil,
            updatedAt: Date())
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary?.resetsAt != nil)
        #expect(usage.secondary?.resetsAt != nil)
    }

    @Test
    func `throws on invalid JSON`() {
        let json = "[{ \"monthly\": {} }]"
        #expect {
            _ = try ChutesUsageFetcher._parseSubscriptionUsageForTesting(Data(json.utf8))
        } throws: { error in
            // DecodingError or ChutesUsageError.parseFailed
            return true
        }
    }
}
