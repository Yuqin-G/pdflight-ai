import Foundation
import Security

public protocol AISecretStore: Sendable {
    func loadAPIKey() throws -> String
    func saveAPIKey(_ apiKey: String) throws
}

public struct KeychainAISecretStore: AISecretStore, Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "dev.pdflight.reader.ai",
        account: String = "openai-compatible-api-key"
    ) {
        self.service = service
        self.account = account
    }

    public func loadAPIKey() throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        return value
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let identity: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let status = SecItemDelete(identity as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(status: status)
            }
            return
        }

        let attributes: [CFString: Any] = [
            kSecValueData: Data(trimmed.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = identity
            attributes.forEach { insertion[$0.key] = $0.value }
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }
}

public struct KeychainError: Error, LocalizedError, Sendable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "Could not access the macOS Keychain: \(message)"
        }
        return "Could not access the macOS Keychain (\(status))."
    }
}

@MainActor
public final class AIConfigurationStore {
    private enum Key {
        static let baseURL = "ai.openaiCompatible.baseURL"
        static let model = "ai.openaiCompatible.model"
    }

    private let userDefaults: UserDefaults
    private let secretStore: any AISecretStore

    public init(
        userDefaults: UserDefaults = .standard,
        secretStore: any AISecretStore = KeychainAISecretStore()
    ) {
        self.userDefaults = userDefaults
        self.secretStore = secretStore
    }

    public func configuration() -> AIProviderConfiguration {
        AIProviderConfiguration(
            baseURL: userDefaults.string(forKey: Key.baseURL) ?? "https://api.openai.com/v1",
            model: userDefaults.string(forKey: Key.model) ?? ""
        )
    }

    public func apiKey() throws -> String {
        try secretStore.loadAPIKey()
    }

    public func save(configuration: AIProviderConfiguration, apiKey: String) throws {
        userDefaults.set(configuration.baseURL, forKey: Key.baseURL)
        userDefaults.set(configuration.model, forKey: Key.model)
        try secretStore.saveAPIKey(apiKey)
    }
}
