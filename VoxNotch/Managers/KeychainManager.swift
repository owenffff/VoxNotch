//
//  KeychainManager.swift
//  VoxNotch
//
//  Secure storage for API keys using macOS Keychain Services
//

import Foundation
import Security

/// Errors that can occur during keychain operations
enum KeychainError: LocalizedError {
  case duplicateItem
  case itemNotFound
  case unexpectedStatus(OSStatus)
  case dataConversionError

  var errorDescription: String? {
    switch self {
    case .duplicateItem:
      return "Item already exists in Keychain"
    case .itemNotFound:
      return "Item not found in Keychain"
    case .unexpectedStatus(let status):
      return "Keychain error: \(status)"
    case .dataConversionError:
      return "Failed to convert data"
    }
  }
}

/// Manages secure storage of API keys in macOS Keychain
final class KeychainManager {

  // MARK: - Types

  /// Supported API key types
  enum KeyType: String, CaseIterable {
    case openAI = "com.ditto.api.openai"

    var displayName: String {
      switch self {
      case .openAI: return "OpenAI API Key"
      }
    }
  }

  // MARK: - Singleton

  static let shared = KeychainManager()

  private init() {}

  // MARK: - Public Methods

  /// Save an API key to the Keychain
  /// - Parameters:
  ///   - apiKey: The API key to store
  ///   - keyType: The type of API key
  func saveAPIKey(_ apiKey: String, for keyType: KeyType) throws {
    guard let data = apiKey.data(using: .utf8) else {
      throw KeychainError.dataConversionError
    }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keyType.rawValue,
      kSecAttrAccount as String: "api_key",
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
    ]

    /// First try to delete any existing item
    SecItemDelete(query as CFDictionary)

    /// Add the new item
    let status = SecItemAdd(query as CFDictionary, nil)

    guard status == errSecSuccess else {
      throw KeychainError.unexpectedStatus(status)
    }
  }

  /// Retrieve an API key from the Keychain
  /// - Parameter keyType: The type of API key to retrieve
  /// - Returns: The API key if found, nil otherwise
  func getAPIKey(for keyType: KeyType) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keyType.rawValue,
      kSecAttrAccount as String: "api_key",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
          let data = result as? Data,
          let apiKey = String(data: data, encoding: .utf8)
    else {
      return nil
    }

    return apiKey
  }

  /// Delete an API key from the Keychain
  /// - Parameter keyType: The type of API key to delete
  func deleteAPIKey(for keyType: KeyType) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keyType.rawValue,
      kSecAttrAccount as String: "api_key"
    ]

    let status = SecItemDelete(query as CFDictionary)

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }

  /// Check if an API key exists in the Keychain
  /// - Parameter keyType: The type of API key to check
  /// - Returns: True if the key exists
  func hasAPIKey(for keyType: KeyType) -> Bool {
    return getAPIKey(for: keyType) != nil
  }

  /// Update an existing API key in the Keychain
  /// - Parameters:
  ///   - apiKey: The new API key
  ///   - keyType: The type of API key to update
  func updateAPIKey(_ apiKey: String, for keyType: KeyType) throws {
    guard let data = apiKey.data(using: .utf8) else {
      throw KeychainError.dataConversionError
    }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keyType.rawValue,
      kSecAttrAccount as String: "api_key"
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: data
    ]

    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    if status == errSecItemNotFound {
      /// Item doesn't exist, create it
      try saveAPIKey(apiKey, for: keyType)
    } else if status != errSecSuccess {
      throw KeychainError.unexpectedStatus(status)
    }
  }

  /// Delete all stored API keys
  func deleteAllAPIKeys() {
    for keyType in KeyType.allCases {
      try? deleteAPIKey(for: keyType)
    }
  }
}
