import Foundation
import MultipeerConnectivity
import CryptoKit

struct PeerManifestEntry: Codable {
    let id: UUID
    let updatedAt: Date
}

struct PeerMessage: Codable {
    enum Kind: String, Codable { case hello, proof, manifest, push }
    let kind: Kind
    var fingerprint: String?
    var publicKey: Data?
    var nonce: Data?
    var deviceName: String?
    var pairingProof: Data?
    var signature: Data?
    var manifest: [PeerManifestEntry]?
    var upserts: [BookmarkItem]?
    var deletes: [UUID]?
}

enum PeerCoding {
    static let serviceType = "bkmkd-sync"
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.dataEncodingStrategy = .base64
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.dataDecodingStrategy = .base64
        return d
    }()
}

@MainActor
final class PairingController: ObservableObject {
    static let shared = PairingController()

    @Published private(set) var trusted: [TrustedPeer] = []
    @Published private(set) var connectedPeers = 0
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var pendingFingerprint: String?
    @Published private(set) var verificationCode: String?

    private(set) var pendingNonce: Data?

    private init() { trusted = TrustStore.shared.all }

    func beginPairing(_ payload: PairingPayload) {
        guard payload.fp == DeviceIdentity.fingerprint(for: payload.pk) else { return }
        TrustStore.shared.add(TrustedPeer(fingerprint: payload.fp, publicKey: payload.pk, name: "Mac", pairedAt: Date()))
        pendingFingerprint = payload.fp
        pendingNonce = payload.pn
        verificationCode = nil
        refreshTrusted()
    }

    func pairingProof() -> Data? {
        guard let pendingNonce else { return nil }
        return DeviceIdentity.sign(pendingNonce)
    }

    func setVerification(_ code: String, for fingerprint: String) {
        guard fingerprint == pendingFingerprint else { return }
        verificationCode = code
    }

    func finishPairing(_ fingerprint: String) {
        guard fingerprint == pendingFingerprint else { return }
        pendingFingerprint = nil
        pendingNonce = nil
        verificationCode = nil
        refreshTrusted()
    }

    func cancelPairing() {
        if let pendingFingerprint { TrustStore.shared.remove(pendingFingerprint) }
        pendingFingerprint = nil
        pendingNonce = nil
        verificationCode = nil
        refreshTrusted()
    }

    func setConnected(_ count: Int) { connectedPeers = count }
    func markSynced() { lastSyncedAt = Date() }
    func refreshTrusted() { trusted = TrustStore.shared.all }

    func unpair(_ fingerprint: String) {
        TrustStore.shared.remove(fingerprint)
        refreshTrusted()
    }
}

final class PeerSync: NSObject {
    private weak var store: BookmarkStore?
    private let peerID = MCPeerID(displayName: DeviceIdentity.deviceName)
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser

    private var ourNonce: [MCPeerID: Data] = [:]
    private var peerKey: [MCPeerID: Data] = [:]
    private var peerFingerprint: [MCPeerID: String] = [:]
    private var authenticated = Set<MCPeerID>()
    private var authorized = Set<MCPeerID>()
    private var ready = Set<MCPeerID>()

    init(store: BookmarkStore) {
        self.store = store
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: PeerCoding.serviceType)
        super.init()
        session.delegate = self
        browser.delegate = self
    }

    func start() {
        browser.startBrowsingForPeers()
    }

    func restart() {
        browser.stopBrowsingForPeers()
        for peer in session.connectedPeers { session.cancelConnectPeer(peer) }
        ourNonce.removeAll(); peerKey.removeAll(); peerFingerprint.removeAll()
        authenticated.removeAll(); authorized.removeAll(); ready.removeAll()
        start()
    }

    private func send(_ message: PeerMessage, to peers: [MCPeerID]) {
        guard !peers.isEmpty, let data = try? PeerCoding.encoder.encode(message) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    @MainActor
    private func sendHello(to peer: MCPeerID) {
        let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        ourNonce[peer] = nonce
        send(PeerMessage(kind: .hello,
                         fingerprint: DeviceIdentity.fingerprint,
                         publicKey: DeviceIdentity.publicKey,
                         nonce: nonce,
                         deviceName: DeviceIdentity.deviceName,
                         pairingProof: PairingController.shared.pairingProof()),
             to: [peer])
    }

    @MainActor
    private func handle(_ message: PeerMessage, from peer: MCPeerID) {
        switch message.kind {
        case .hello: handleHello(message, from: peer)
        case .proof: handleProof(message, from: peer)
        case .push:
            guard ready.contains(peer) else { return }
            store?.applyPeerPush(upserts: message.upserts ?? [], deletes: message.deletes ?? [])
            PairingController.shared.markSynced()
        case .manifest:
            break
        }
    }

    @MainActor
    private func handleHello(_ message: PeerMessage, from peer: MCPeerID) {
        guard let pk = message.publicKey, let theirNonce = message.nonce,
              let fp = message.fingerprint, fp == DeviceIdentity.fingerprint(for: pk),
              TrustStore.shared.isTrusted(fp),
              TrustStore.shared.publicKey(for: fp) == pk else {
            reject(peer); return
        }
        peerKey[peer] = pk
        peerFingerprint[peer] = fp
        authorized.insert(peer)
        PairingController.shared.setVerification(DeviceIdentity.shortAuthString(DeviceIdentity.publicKey, pk), for: fp)
        replyProof(to: peer, theirNonce: theirNonce)
        maybeReady(peer)
    }

    @MainActor
    private func handleProof(_ message: PeerMessage, from peer: MCPeerID) {
        guard let sig = message.signature,
              let pk = peerKey[peer],
              let myNonce = ourNonce[peer],
              DeviceIdentity.verify(sig, of: myNonce, publicKey: pk) else {
            reject(peer); return
        }
        authenticated.insert(peer)
        maybeReady(peer)
    }

    @MainActor
    private func replyProof(to peer: MCPeerID, theirNonce: Data) {
        send(PeerMessage(kind: .proof,
                         fingerprint: DeviceIdentity.fingerprint,
                         signature: DeviceIdentity.sign(theirNonce)),
             to: [peer])
    }

    @MainActor
    private func maybeReady(_ peer: MCPeerID) {
        guard authenticated.contains(peer), authorized.contains(peer), !ready.contains(peer) else { return }
        ready.insert(peer)
        PairingController.shared.setConnected(ready.count)
        if let fp = peerFingerprint[peer] { PairingController.shared.finishPairing(fp) }
        sendManifest(to: peer)
    }

    @MainActor
    private func sendManifest(to peer: MCPeerID) {
        guard let store else { return }
        let entries = store.items.map { PeerManifestEntry(id: $0.id, updatedAt: $0.updatedAt) }
        send(PeerMessage(kind: .manifest, manifest: entries), to: [peer])
    }

    @MainActor
    private func reject(_ peer: MCPeerID) {
        session.cancelConnectPeer(peer)
        clear(peer)
    }

    @MainActor
    private func clear(_ peer: MCPeerID) {
        ourNonce[peer] = nil
        peerKey[peer] = nil
        peerFingerprint[peer] = nil
        authenticated.remove(peer)
        authorized.remove(peer)
        ready.remove(peer)
        PairingController.shared.setConnected(ready.count)
    }
}

extension PeerSync: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let fp = info?["fp"] else { return }
        Task { @MainActor in
            let pending = PairingController.shared.pendingFingerprint == fp
            guard pending || TrustStore.shared.isTrusted(fp) else { return }
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

extension PeerSync: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            Task { @MainActor in self.sendHello(to: peerID) }
        case .notConnected:
            Task { @MainActor in self.clear(peerID) }
        default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? PeerCoding.decoder.decode(PeerMessage.self, from: data) else { return }
        Task { @MainActor in self.handle(message, from: peerID) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
