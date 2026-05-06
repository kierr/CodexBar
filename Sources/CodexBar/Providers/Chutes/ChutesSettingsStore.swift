import CodexBarCore
import Foundation

extension SettingsStore {
    var chutesAPIToken: String {
        get { self.configSnapshot.providerConfig(for: .chutes)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .chutes) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .chutes, field: "apiKey", value: newValue)
        }
    }
}
