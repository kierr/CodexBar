import Foundation
import Testing
@testable import CodexBarCore

// MARK: - 3-tier mapping tests

struct ZaiThreeTierMappingTests {
    private func makeLimit(
        type: ZaiLimitType,
        unit: ZaiLimitUnit = .hours,
        number: Int = 5,
        usage: Int? = 100,
        currentValue: Int? = 20,
        remaining: Int? = 80,
        percentage: Double = 20,
        resetTime: Date? = nil) -> ZaiLimitEntry
    {
        ZaiLimitEntry(
            type: type,
            unit: unit,
            number: number,
            usage: usage,
            currentValue: currentValue,
            remaining: remaining,
            percentage: percentage,
            usageDetails: [],
            nextResetTime: resetTime)
    }

    @Test
    func `two tier maps token to primary and time to secondary`() {
        let now = Date()
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: self.makeLimit(type: .tokensLimit, unit: .hours, number: 5),
            weeklyLimit: nil,
            timeLimit: self.makeLimit(type: .timeLimit, unit: .days, number: 30),
            planName: "Pro",
            updatedAt: now)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.windowMinutes == 300)
        #expect(usage.secondary != nil)
        #expect(usage.tertiary == nil)
    }

    @Test
    func `three tier maps tools to secondary and weekly to tertiary`() {
        let now = Date()
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: self.makeLimit(type: .tokensLimit, unit: .hours, number: 5),
            weeklyLimit: self.makeLimit(type: .tokensLimit, unit: .days, number: 7),
            timeLimit: self.makeLimit(type: .timeLimit, unit: .days, number: 30),
            planName: "Max",
            updatedAt: now)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.windowMinutes == 300)
        // Secondary = MCP (TIME_LIMIT — windowMinutes is nil for time limits)
        #expect(usage.secondary != nil)
        #expect(usage.secondary?.windowMinutes == nil)
        // Tertiary = weekly (TOKENS_LIMIT, 7 days)
        #expect(usage.tertiary?.windowMinutes == 10080)
    }

    @Test
    func `no token limit promotes time to primary`() {
        let now = Date()
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: nil,
            weeklyLimit: nil,
            timeLimit: self.makeLimit(type: .timeLimit, unit: .days, number: 30),
            planName: nil,
            updatedAt: now)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary != nil)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
    }

    @Test
    func `empty limits produce zero primary`() {
        let now = Date()
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: nil,
            weeklyLimit: nil,
            timeLimit: nil,
            planName: nil,
            updatedAt: now)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 0)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
    }
}

// MARK: - Identity priority tests

struct ZaiIdentityPriorityTests {
    @Test
    func `subscription name takes priority over plan name`() {
        let sub = ZaiSubscriptionEntry(
            productName: "GLM Coding Max",
            status: "VALID",
            billingCycle: "MONTHLY",
            nextRenewTime: nil,
            autoRenew: true,
            validFrom: nil,
            validTo: nil)
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: nil,
            planName: "Pro",
            subscription: sub,
            updatedAt: Date())

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.identity?.loginMethod == "GLM Coding Max")
    }

    @Test
    func `plan name used when no subscription`() {
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: nil,
            planName: "Pro",
            updatedAt: Date())

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.identity?.loginMethod == "Pro")
    }

    @Test
    func `level used as last resort`() {
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: nil,
            planName: nil,
            level: "max",
            updatedAt: Date())

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.identity?.loginMethod == "max")
    }

    @Test
    func `nil identity when all empty`() {
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: nil,
            planName: "",
            level: "",
            updatedAt: Date())

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.identity?.loginMethod == nil)
    }
}

// MARK: - Level + multiple TOKENS_LIMIT parsing tests

struct ZaiQuotaLevelParsingTests {
    @Test
    func `parses level field`() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 30,
                "nextResetTime": 1768507567547
              }
            ],
            "planName": "Pro",
            "level": "max"
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.level == "max")
        #expect(snapshot.planName == "Pro")
    }

    @Test
    func `parses multiple TOKENS_LIMIT entries`() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 30,
                "nextResetTime": 1768507567547
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 1,
                "number": 7,
                "percentage": 10,
                "nextResetTime": 1768907567547
              },
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 100,
                "currentValue": 7,
                "remaining": 93,
                "percentage": 7,
                "usageDetails": []
              }
            ]
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        // Shortest window (5-hour) should be tokenLimit.
        #expect(snapshot.tokenLimit?.windowMinutes == 300)
        #expect(snapshot.tokenLimit?.percentage == 30)
        // Longer window (7-day) should be weeklyLimit.
        #expect(snapshot.weeklyLimit?.windowMinutes == 10080)
        #expect(snapshot.weeklyLimit?.percentage == 10)
        // TIME_LIMIT preserved.
        #expect(snapshot.timeLimit != nil)
    }

    @Test
    func `parses 3+ TOKENS_LIMIT keeps shortest and longest only`() throws {
        // With 3 TOKENS_LIMIT entries, only shortest and longest should be preserved.
        // The middle entry (medium window) should be discarded.
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 30,
                "nextResetTime": 1768507567547
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 12,
                "percentage": 15,
                "nextResetTime": 1768607567547
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 1,
                "number": 7,
                "percentage": 10,
                "nextResetTime": 1768907567547
              },
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 100,
                "currentValue": 7,
                "remaining": 93,
                "percentage": 7,
                "usageDetails": []
              }
            ]
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        // Shortest window (5-hour = 300 min) should be tokenLimit.
        #expect(snapshot.tokenLimit?.windowMinutes == 300)
        #expect(snapshot.tokenLimit?.percentage == 30)
        // Longest window (7-day = 10080 min) should be weeklyLimit.
        #expect(snapshot.weeklyLimit?.windowMinutes == 10080)
        #expect(snapshot.weeklyLimit?.percentage == 10)
        // Middle TOKENS_LIMIT (12-hour = 720 min) should NOT be preserved.
        #expect(snapshot.tokenLimit?.windowMinutes != 720)
        #expect(snapshot.weeklyLimit?.windowMinutes != 720)
        // TIME_LIMIT should still be preserved.
        #expect(snapshot.timeLimit != nil)
    }

    @Test
    func `single TOKENS_LIMIT has no weekly`() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 45,
                "nextResetTime": 1768507567547
              }
            ]
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.tokenLimit != nil)
        #expect(snapshot.weeklyLimit == nil)
    }

    @Test
    func `missing level parses as nil`() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [],
            "planName": "Pro"
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.level == nil)
    }
}

// MARK: - Subscription parsing tests

struct ZaiSubscriptionParsingTests {
    @Test
    func `subscription entry isActive only for VALID`() {
        let statuses = ["VALID", "EXPIRED", "PENDING", "CANCELLED", "SUSPENDED", "valid", ""]
        let results = statuses.map { status in
            ZaiSubscriptionEntry(
                productName: "P", status: status,
                billingCycle: nil, nextRenewTime: nil, autoRenew: false,
                validFrom: nil, validTo: nil).isActive
        }
        #expect(results == [true, false, false, false, false, false, false])
    }
}

// MARK: - Subscription response parsing tests

struct ZaiSubscriptionResponseParsingTests {
    @Test
    func `parses valid subscription response`() {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": [
            {
              "productName": "GLM Coding Max",
              "status": "VALID",
              "billingCycle": "MONTHLY",
              "nextRenewTime": "2026-04-24",
              "autoRenew": 1,
              "valid": "2026-03-24 01:41:28-2026-06-24 01:41:28"
            }
          ],
          "success": true
        }
        """

        let entry = ZaiSubscriptionFetcher.parseSubscription(from: Data(json.utf8))

        #expect(entry?.productName == "GLM Coding Max")
        #expect(entry?.status == "VALID")
        #expect(entry?.isActive == true)
        #expect(entry?.billingCycle == "MONTHLY")
        #expect(entry?.nextRenewTime == "2026-04-24")
        #expect(entry?.autoRenew == true)
        #expect(entry?.validFrom == "2026-03-24 01:41:28")
        #expect(entry?.validTo == "2026-06-24 01:41:28")
    }

    @Test
    func `prefers active subscription over expired`() {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": [
            {
              "productName": "Old Plan",
              "status": "EXPIRED",
              "billingCycle": "MONTHLY"
            },
            {
              "productName": "Current Plan",
              "status": "VALID",
              "billingCycle": "MONTHLY"
            }
          ],
          "success": true
        }
        """

        let entry = ZaiSubscriptionFetcher.parseSubscription(from: Data(json.utf8))

        #expect(entry?.productName == "Current Plan")
        #expect(entry?.isActive == true)
    }

    @Test
    func `returns nil for error response`() {
        let json = """
        { "code": 401, "msg": "Unauthorized", "success": false }
        """

        let entry = ZaiSubscriptionFetcher.parseSubscription(from: Data(json.utf8))

        #expect(entry == nil)
    }

    @Test
    func `returns nil for empty data`() {
        let entry = ZaiSubscriptionFetcher.parseSubscription(from: Data())

        #expect(entry == nil)
    }

    @Test
    func `returns nil for empty subscription list`() {
        let json = """
        { "code": 200, "msg": "OK", "data": [], "success": true }
        """

        let entry = ZaiSubscriptionFetcher.parseSubscription(from: Data(json.utf8))

        #expect(entry == nil)
    }

    @Test
    func `returns nil when product name is empty`() {
        let json = """
        {
          "code": 200,
          "msg": "OK",
          "data": [{ "productName": "", "status": "VALID" }],
          "success": true
        }
        """

        let entry = ZaiSubscriptionFetcher.parseSubscription(from: Data(json.utf8))

        #expect(entry == nil)
    }

    @Test
    func `handles missing optional fields`() {
        let json = """
        {
          "code": 200,
          "msg": "OK",
          "data": [{ "productName": "Basic", "status": "VALID" }],
          "success": true
        }
        """

        let entry = ZaiSubscriptionFetcher.parseSubscription(from: Data(json.utf8))

        #expect(entry?.productName == "Basic")
        #expect(entry?.billingCycle == nil)
        #expect(entry?.nextRenewTime == nil)
        #expect(entry?.autoRenew == false)
        #expect(entry?.validFrom == nil)
        #expect(entry?.validTo == nil)
    }

    @Test
    func `handles missing msg field`() {
        let json = """
        {
          "code": 200,
          "data": [{ "productName": "Pro", "status": "VALID" }],
          "success": true
        }
        """

        let entry = ZaiSubscriptionFetcher.parseSubscription(from: Data(json.utf8))

        #expect(entry?.productName == "Pro")
    }

    @Test
    func `valid field regex handles varied formats`() {
        // Standard format
        let json1 = """
        {
          "code": 200, "msg": "OK", "success": true,
          "data": [{ "productName": "P", "status": "VALID", "valid": "2026-03-24 01:41:28-2026-06-24 01:41:28" }]
        }
        """
        let e1 = ZaiSubscriptionFetcher.parseSubscription(from: Data(json1.utf8))
        #expect(e1?.validFrom == "2026-03-24 01:41:28")
        #expect(e1?.validTo == "2026-06-24 01:41:28")

        // Extra spaces around separator
        let json2 = """
        {
          "code": 200, "msg": "OK", "success": true,
          "data": [{ "productName": "P", "status": "VALID", "valid": "2026-03-24 01:41:28 - 2026-06-24 01:41:28" }]
        }
        """
        let e2 = ZaiSubscriptionFetcher.parseSubscription(from: Data(json2.utf8))
        #expect(e2?.validFrom == "2026-03-24 01:41:28")
        #expect(e2?.validTo == "2026-06-24 01:41:28")
    }

    @Test
    func `valid field regex returns nil for malformed input`() {
        let cases = ["garbage", "2026-03-24", "2026-03-24 01:41:28-", "", "foo-bar"]
        for invalid in cases {
            let json = """
            {
              "code": 200, "msg": "OK", "success": true,
              "data": [{ "productName": "P", "status": "VALID", "valid": "\(invalid)" }]
            }
            """
            let entry = ZaiSubscriptionFetcher.parseSubscription(from: Data(json.utf8))
            #expect(entry?.validFrom == nil, "Expected nil validFrom for: \(invalid)")
            #expect(entry?.validTo == nil, "Expected nil validTo for: \(invalid)")
        }
    }
}

// MARK: - Snapshot enrichment tests

struct ZaiSnapshotEnrichmentTests {
    private func makeLimit(type: ZaiLimitType, unit: ZaiLimitUnit, number: Int) -> ZaiLimitEntry {
        ZaiLimitEntry(
            type: type, unit: unit, number: number,
            usage: 100, currentValue: 20, remaining: 80, percentage: 20,
            usageDetails: [], nextResetTime: nil)
    }

    @Test
    func `snapshot preserves subscription and level`() {
        let sub = ZaiSubscriptionEntry(
            productName: "Pro",
            status: "VALID",
            billingCycle: "MONTHLY",
            nextRenewTime: nil,
            autoRenew: true,
            validFrom: nil,
            validTo: nil)

        let snapshot = ZaiUsageSnapshot(
            tokenLimit: nil,
            weeklyLimit: nil,
            timeLimit: nil,
            planName: "Pro",
            level: "max",
            subscription: sub,
            updatedAt: Date())

        #expect(snapshot.subscription?.productName == "Pro")
        #expect(snapshot.level == "max")
    }

    @Test
    func `snapshot preserves weeklyLimit`() {
        let weekly = self.makeLimit(type: .tokensLimit, unit: .days, number: 7)
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: self.makeLimit(type: .tokensLimit, unit: .hours, number: 5),
            weeklyLimit: weekly,
            timeLimit: nil,
            planName: nil,
            updatedAt: Date())

        #expect(snapshot.weeklyLimit?.windowMinutes == 10080)
    }
}
