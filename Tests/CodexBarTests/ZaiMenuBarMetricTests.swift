import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ZaiMenuBarMetricResolverTests {
    @Test
    func `automatic selects most constrained window`() {
        let primary = RateWindow(usedPercent: 30, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 70, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            providerCost: nil,
            zaiUsage: nil,
            updatedAt: Date(),
            identity: nil)

        let result = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .zai,
            snapshot: snapshot,
            supportsAverage: false)

        // Secondary (70%) is more constrained than primary (30%).
        #expect(result?.usedPercent == 70)
    }

    @Test
    func `primary preference returns primary window`() {
        let primary = RateWindow(usedPercent: 30, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 70, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            providerCost: nil,
            zaiUsage: nil,
            updatedAt: Date(),
            identity: nil)

        let result = MenuBarMetricWindowResolver.rateWindow(
            preference: .primary,
            provider: .zai,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(result?.usedPercent == 30)
    }

    @Test
    func `secondary preference returns secondary window`() {
        let primary = RateWindow(usedPercent: 30, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 70, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            providerCost: nil,
            zaiUsage: nil,
            updatedAt: Date(),
            identity: nil)

        let result = MenuBarMetricWindowResolver.rateWindow(
            preference: .secondary,
            provider: .zai,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(result?.usedPercent == 70)
    }

    @Test
    func `tertiary preference returns tertiary window for zai`() {
        let primary = RateWindow(usedPercent: 30, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let tertiary = RateWindow(usedPercent: 90, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            providerCost: nil,
            zaiUsage: nil,
            updatedAt: Date(),
            identity: nil)

        let result = MenuBarMetricWindowResolver.rateWindow(
            preference: .tertiary,
            provider: .zai,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(result?.usedPercent == 90)
    }

    @Test
    func `automatic with nil secondary returns primary`() {
        let primary = RateWindow(usedPercent: 30, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: nil,
            zaiUsage: nil,
            updatedAt: Date(),
            identity: nil)

        let result = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .zai,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(result?.usedPercent == 30)
    }
}

@MainActor
struct ZaiMenuBarMetricPreferenceTests {
    private func makeSettings(suiteName: String) throws -> SettingsStore {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let configStore = testConfigStore(suiteName: suiteName)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore())
    }

    @Test
    func `zai defaults to automatic`() throws {
        let settings = try self.makeSettings(suiteName: "ZaiMetricPref-default")

        let preference = settings.menuBarMetricPreference(for: .zai)

        #expect(preference == .automatic)
    }

    @Test
    func `zai allows setting secondary`() throws {
        let settings = try self.makeSettings(suiteName: "ZaiMetricPref-secondary")

        settings.setMenuBarMetricPreference(.secondary, for: .zai)
        let preference = settings.menuBarMetricPreference(for: .zai)

        #expect(preference == .secondary)
    }

    @Test
    func `zai tertiary blocked without snapshot`() throws {
        let settings = try self.makeSettings(suiteName: "ZaiMetricPref-tertiary-blocked")

        // Static check: zai supports tertiary.
        #expect(settings.menuBarMetricSupportsTertiary(for: .zai) == true)

        // Snapshot check: nil snapshot → no tertiary.
        #expect(settings.menuBarMetricSupportsTertiary(for: .zai, snapshot: nil) == false)
    }

    @Test
    func `zai tertiary allowed with snapshot tertiary`() throws {
        let settings = try self.makeSettings(suiteName: "ZaiMetricPref-tertiary-allowed")

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: RateWindow(usedPercent: 30, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            providerCost: nil,
            zaiUsage: nil,
            updatedAt: Date(),
            identity: nil)

        #expect(settings.menuBarMetricSupportsTertiary(for: .zai, snapshot: snapshot) == true)
    }

    @Test
    func `zai tertiary preference falls back to automatic without snapshot`() throws {
        let settings = try self.makeSettings(suiteName: "ZaiMetricPref-tertiary-fallback")

        settings.setMenuBarMetricPreference(.tertiary, for: .zai)
        // With no snapshot, tertiary should fall back.
        let resolved = settings.menuBarMetricPreference(for: .zai, snapshot: nil)

        #expect(resolved == .automatic)
    }
}
