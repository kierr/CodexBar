import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum ZaiProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .zai,
            metadata: ProviderMetadata(
                id: .zai,
                displayName: "z.ai",
                sessionLabel: "5-hour",
                weeklyLabel: "MCP",
                opusLabel: "Weekly",
                supportsOpus: true,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show z.ai usage",
                cliName: "zai",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                dashboardURL: "https://z.ai/manage-apikey/subscription",
                statusPageURL: nil,
                statusLinkURL: "https://z.ai"),
            branding: ProviderBranding(
                iconStyle: .zai,
                iconResourceName: "ProviderIcon-zai",
                color: ProviderColor(red: 232 / 255, green: 90 / 255, blue: 106 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "z.ai cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [ZaiAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "zai",
                aliases: ["z.ai"],
                versionDetector: nil))
    }
}

struct ZaiAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "zai.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw ZaiSettingsError.missingToken
        }
        let region = context.settings?.zai?.apiRegion ?? .global

        // Fetch quota (required). Subscription is best-effort and should not block.
        let usage = try await ZaiUsageFetcher.fetchUsage(
            apiKey: apiKey,
            region: region,
            environment: context.env)

        // Enrich with subscription in the background with a short timeout.
        // This ensures slow/unavailable subscription API never delays quota data.
        let subscription = await withTaskGroup(of: ZaiSubscriptionEntry?.self) { group in
            group.addTask {
                await ZaiSubscriptionFetcher.fetchSubscription(
                    apiKey: apiKey,
                    region: region,
                    environment: context.env)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s cap
                return nil
            }
            if let first = await group.next() {
                group.cancelAll()
                return first
            }
            return nil
        }

        let enriched = ZaiUsageSnapshot(
            tokenLimit: usage.tokenLimit,
            weeklyLimit: usage.weeklyLimit,
            timeLimit: usage.timeLimit,
            planName: usage.planName,
            level: usage.level,
            subscription: subscription,
            updatedAt: usage.updatedAt)

        return self.makeResult(
            usage: enriched.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.zaiToken(environment: environment)
    }
}
