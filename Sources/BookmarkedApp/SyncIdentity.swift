import Foundation
import CryptoKit
import Security
#if canImport(UIKit)
import UIKit
#endif

enum Keychain {
    static func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func write(_ data: Data, service: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}

enum DeviceIdentity {
    private static let service = "com.swair.bookmarked.sync"
    private static let account = "device-ed25519-private-key"
    private static let nameKey = "syncDeviceName"
    private static var cached: Curve25519.Signing.PrivateKey?

    static var privateKey: Curve25519.Signing.PrivateKey {
        if let cached { return cached }
        if let data = Keychain.read(service: service, account: account),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            cached = key
            return key
        }
        let key = Curve25519.Signing.PrivateKey()
        Keychain.write(key.rawRepresentation, service: service, account: account)
        cached = key
        return key
    }

    static var publicKey: Data { privateKey.publicKey.rawRepresentation }

    static var fingerprint: String { fingerprint(for: publicKey) }

    static func fingerprint(for publicKey: Data) -> String {
        SHA256.hash(data: publicKey).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func sign(_ data: Data) -> Data {
        (try? privateKey.signature(for: data)) ?? Data()
    }

    static func verify(_ signature: Data, of data: Data, publicKey: Data) -> Bool {
        guard !signature.isEmpty,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: data)
    }

    static func shortAuthString(_ a: Data, _ b: Data) -> String {
        let ordered = a.lexicographicallyPrecedes(b) ? [a, b] : [b, a]
        var combined = Data()
        ordered.forEach { combined.append($0) }
        let value = SHA256.hash(data: combined).prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06d", value % 1_000_000)
    }

    static var deviceName: String {
        get {
            let stored = UserDefaults.standard.string(forKey: nameKey)
            if let stored, !stored.isEmpty { return stored }
            return defaultName
        }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    static var defaultName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}

struct TrustedPeer: Codable, Identifiable {
    let fingerprint: String
    let publicKey: Data
    var name: String
    var pairedAt: Date
    var id: String { fingerprint }
}

final class TrustStore {
    static let shared = TrustStore()
    private let defaultsKey = "syncTrustedPeers"
    private let queue = DispatchQueue(label: "com.swair.bookmarked.truststore")
    private var peers: [String: TrustedPeer]

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([TrustedPeer].self, from: data) {
            peers = Dictionary(list.map { ($0.fingerprint, $0) }, uniquingKeysWith: { a, _ in a })
        } else {
            peers = [:]
        }
    }

    var all: [TrustedPeer] { queue.sync { peers.values.sorted { $0.pairedAt > $1.pairedAt } } }
    var isEmpty: Bool { queue.sync { peers.isEmpty } }

    func isTrusted(_ fingerprint: String) -> Bool { queue.sync { peers[fingerprint] != nil } }
    func publicKey(for fingerprint: String) -> Data? { queue.sync { peers[fingerprint]?.publicKey } }

    func add(_ peer: TrustedPeer) {
        queue.sync {
            peers[peer.fingerprint] = peer
            persist()
        }
    }

    func remove(_ fingerprint: String) {
        queue.sync {
            peers.removeValue(forKey: fingerprint)
            persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(peers.values)) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

struct PairingPayload: Codable {
    let v: Int
    let fp: String
    let pk: Data
    let pn: Data

    var json: String {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        guard let data = try? encoder.encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func parse(_ string: String) -> PairingPayload? {
        guard let data = string.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        return try? decoder.decode(PairingPayload.self, from: data)
    }
}
