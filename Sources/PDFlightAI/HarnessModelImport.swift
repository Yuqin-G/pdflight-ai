import Foundation
import Yams

/// Reads Harness settings locally without starting Harness or changing its
/// configuration. Secrets are returned only to the caller, never logged.
public enum HarnessModelImport {
    public struct Route: Codable, Sendable, Equatable, Identifiable {
        public let provider: String
        public let providerName: String?
        public let model: String
        public let name: String
        public let api: String
        public let baseURL: String
        public let reasoningEfforts: [String]?
        public let forceAdaptiveThinking: Bool?
        public let maxTokens: Int?
        public var id: String { provider + "/" + model }
        public var isSupported: Bool { ["openai-completions", "openai-responses", "anthropic-messages"].contains(api) }
    }
    public struct Catalog: Sendable {
        public let routes: [Route]
        public let secrets: [String: String]
        public let selectedID: String
        public let defaultAccessMode: AIChatAccessMode?
    }
    public struct Selection: Sendable {
        public let provider: String
        public let api: String
        public let configuration: AIProviderConfiguration
        public let apiKey: String
    }

    public enum ImportError: Error, Equatable {
        case invalidSettings
        case missingSelection
        case missingProvider(String)
        case unsupportedAPI(String)
        case missingCredential(String)
    }

    public static func read(profile: URL, credentials: URL?) throws -> Selection {
        let source = try String(contentsOf: profile, encoding: .utf8)
        guard let patches = try Yams.load(yaml: source) as? [[String: Any]] else {
            throw ImportError.invalidSettings
        }
        guard let selected = patches.last(where: { $0["id"] as? String == "agent-default-model" })?["config"] as? [String: Any],
              let provider = selected["provider"] as? String, !provider.isEmpty,
              let model = selected["model"] as? String, !model.isEmpty else {
            throw ImportError.missingSelection
        }
        guard let llm = patches.last(where: { $0["id"] as? String == "llm-pi-ai" })?["config"] as? [String: Any],
              let providers = llm["providers"] as? [String: Any],
              let item = providers[provider] as? [String: Any],
              let baseURL = item["baseURL"] as? String,
              let api = item["api"] as? String else { throw ImportError.missingProvider(provider) }
        guard api == "openai-completions" else { throw ImportError.unsupportedAPI(api) }
        var secret = ""
        if let name = item["apiKeyEnv"] as? String, !name.isEmpty {
            if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
                secret = value
            } else if let credentials {
                let yaml = try String(contentsOf: credentials, encoding: .utf8)
                let root = try Yams.load(yaml: yaml) as? [String: Any]
                guard let refs = root?["refs"] as? [String: Any], let value = refs[name] as? String, !value.isEmpty else {
                    throw ImportError.missingCredential(name)
                }
                secret = value
            } else { throw ImportError.missingCredential(name) }
        }
        return Selection(provider: provider, api: api,
            configuration: AIProviderConfiguration(baseURL: baseURL, model: model), apiKey: secret)
    }

    public static func readCatalog(profile: URL, credentials: URL?) throws -> Catalog {
        let source = try String(contentsOf: profile, encoding: .utf8)
        guard let patches = try Yams.load(yaml: source) as? [[String: Any]],
              let selected = patches.last(where: { $0["id"] as? String == "agent-default-model" })?["config"] as? [String: Any],
              let selectedProvider = selected["provider"] as? String, let selectedModel = selected["model"] as? String,
              let llm = patches.last(where: { $0["id"] as? String == "llm-pi-ai" })?["config"] as? [String: Any],
              let providers = llm["providers"] as? [String: Any] else { throw ImportError.invalidSettings }
        var refs: [String: Any] = [:]
        if let credentials, FileManager.default.fileExists(atPath: credentials.path) {
            let root = try Yams.load(yaml: String(contentsOf: credentials, encoding: .utf8)) as? [String: Any]
            refs = root?["refs"] as? [String: Any] ?? [:]
        }
        var routes: [Route] = []; var secrets: [String: String] = [:]
        for provider in providers.keys.sorted() {
            guard let item = providers[provider] as? [String: Any],
                  let baseURL = item["baseURL"] as? String, let api = item["api"] as? String,
                  let models = item["models"] as? [[String: Any]] else { continue }
            if let keyName = item["apiKeyEnv"] as? String {
                let secret = ProcessInfo.processInfo.environment[keyName] ?? refs[keyName] as? String
                if let secret, !secret.isEmpty { secrets[provider] = secret }
            }
            let providerName = item["displayName"] as? String
            for item in models {
                guard let model = item["id"] as? String, !model.isEmpty else { continue }
                let effortMap = item["reasoningEfforts"] as? [String: Any] ?? [:]
                let orderedEfforts = ["off", "low", "medium", "high", "xhigh", "max"].filter { effortMap[$0] != nil }
                let compat = item["compat"] as? [String: Any]
                routes.append(Route(provider: provider, providerName: providerName, model: model, name: item["name"] as? String ?? model,
                                    api: api, baseURL: baseURL, reasoningEfforts: orderedEfforts.isEmpty ? nil : orderedEfforts,
                                    forceAdaptiveThinking: compat?["forceAdaptiveThinking"] as? Bool,
                                    maxTokens: item["maxTokens"] as? Int))
            }
        }
        let permission = patches.last(where: { $0["name"] as? String == "@deepseek-ai/dsh-permission-presets" && ($0["disabled"] as? Bool) != true })?["config"] as? [String: Any]
        let preset = permission?["defaultPreset"] as? String
        let presetConfig = (permission?["presets"] as? [String: Any])?[preset ?? ""] as? [String: Any]
        let mode: AIChatAccessMode? = preset == "danger-full-access" && presetConfig?["sandbox"] as? String == "danger-full-access" && presetConfig?["approval"] as? String == "never" ? .fullAccess : (preset == "read-only" ? .readOnly : nil)
        return Catalog(routes: routes, secrets: secrets, selectedID: selectedProvider + "/" + selectedModel, defaultAccessMode: mode)
    }
}
