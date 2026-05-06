import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct ChutesProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .chutes

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "api" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.chutesAPIToken
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if ChutesSettingsReader.apiKey(environment: context.environment) != nil {
            return true
        }
        return context.settings.configSnapshot.providerConfig(for: .chutes)?.sanitizedAPIKey != nil
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "chutes-api-key",
                title: "API key",
                subtitle: "Stored in ~/.codexbar/config.json. You can also set CHUTES_API_KEY.",
                kind: .secure,
                placeholder: "cpk_...",
                binding: context.stringBinding(\.chutesAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "chutes-open-dashboard",
                        title: "Open Chutes Dashboard",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://chutes.ai/app/settings") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
