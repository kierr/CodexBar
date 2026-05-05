import CodexBarCore
import Testing

struct ChutesSettingsReaderTests {
    @Test
    func `reads CHUTES_API_KEY`() {
        let env = ["CHUTES_API_KEY": "cpk_abc123"]
        #expect(ChutesSettingsReader.apiKey(environment: env) == "cpk_abc123")
    }

    @Test
    func `falls back to CHUTES_KEY`() {
        let env = ["CHUTES_KEY": "cpk_fallback"]
        #expect(ChutesSettingsReader.apiKey(environment: env) == "cpk_fallback")
    }

    @Test
    func `CHUTES_API_KEY takes priority over CHUTES_KEY`() {
        let env = ["CHUTES_API_KEY": "cpk-primary", "CHUTES_KEY": "cpk-secondary"]
        #expect(ChutesSettingsReader.apiKey(environment: env) == "cpk-primary")
    }

    @Test
    func `trims whitespace`() {
        let env = ["CHUTES_API_KEY": "  cpk-trimmed  "]
        #expect(ChutesSettingsReader.apiKey(environment: env) == "cpk-trimmed")
    }

    @Test
    func `strips double quotes`() {
        let env = ["CHUTES_API_KEY": "\"cpk-quoted\""]
        #expect(ChutesSettingsReader.apiKey(environment: env) == "cpk-quoted")
    }

    @Test
    func `strips single quotes`() {
        let env = ["CHUTES_KEY": "'cpk-single'"]
        #expect(ChutesSettingsReader.apiKey(environment: env) == "cpk-single")
    }

    @Test
    func `returns nil when no key present`() {
        #expect(ChutesSettingsReader.apiKey(environment: [:]) == nil)
    }

    @Test
    func `returns nil for empty key`() {
        let env = ["CHUTES_API_KEY": ""]
        #expect(ChutesSettingsReader.apiKey(environment: env) == nil)
    }

    @Test
    func `returns nil for whitespace-only key`() {
        let env = ["CHUTES_API_KEY": "   "]
        #expect(ChutesSettingsReader.apiKey(environment: env) == nil)
    }

    @Test
    func `reads CHUTES_API_HOST override`() {
        let env = ["CHUTES_API_HOST": "  https://custom.api.host  "]
        #expect(ChutesSettingsReader.apiHost(environment: env) == "https://custom.api.host")
    }

    @Test
    func `apiHost returns nil when absent`() {
        #expect(ChutesSettingsReader.apiHost(environment: [:]) == nil)
    }
}

struct ChutesProviderTokenResolverTests {
    @Test
    func `resolves from environment`() {
        let env = ["CHUTES_API_KEY": "cpk-resolve-test"]
        let resolution = ProviderTokenResolver.chutesResolution(environment: env)
        #expect(resolution?.token == "cpk-resolve-test")
        #expect(resolution?.source == .environment)
    }

    @Test
    func `returns nil when key absent`() {
        let resolution = ProviderTokenResolver.chutesResolution(environment: [:])
        #expect(resolution == nil)
    }
}
