import Foundation
import MultipeerConnectivity
import CryptoKit
import Combine

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
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    struct PendingPairing: Identifiable {
        let id = UUID()
        let fingerprint: String
        let name: String
        let sas: String
    }

    @Published var isPairing = false
    @Published private(set) var pairingNonce: Data?
    @Published var pending: PendingPairing?
    @Published private(set) var trusted: [TrustedPeer] = []

    private var onConfirm: (() -> Void)?
    private var onDeny: (() -> Void)?

    private init() { trusted = TrustStore.shared.all }

    var pairingPayloadJSON: String {
        guard let nonce = pairingNonce else { return "" }
        return PairingPayload(v: 2, fp: DeviceIdentity.fingerprint, pk: DeviceIdentity.publicKey, pn: nonce).json
    }

    @discardableResult
    func beginPairing() -> Data {
        let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        pairingNonce = nonce
        isPairing = true
        return nonce
    }

    func endPairing() {
        isPairing = false
        pairingNonce = nil
        pending = nil
        onConfirm = nil
        onDeny = nil
    }

    func requestConfirmation(_ pairing: PendingPairing, confirm: @escaping () -> Void, deny: @escaping () -> Void) {
        pending = pairing
        onConfirm = confirm
        onDeny = deny
    }

    func confirm() {
        onConfirm?()
        pending = nil
        onConfirm = nil
        onDeny = nil
        refreshTrusted()
    }

    func deny() {
        onDeny?()
        pending = nil
        onConfirm = nil
        onDeny = nil
    }

    func refreshTrusted() { trusted = TrustStore.shared.all }

    func unpair(_ fingerprint: String) {
        TrustStore.shared.remove(fingerprint)
        refreshTrusted()
    }
}

final class PeerSync: NSObject {
    private weak var store: BookmarkStore?
    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private var lastManifest: [PeerManifestEntry] = []

    private var ourNonce: [MCPeerID: Data] = [:]
    private var peerKey: [MCPeerID: Data] = [:]
    private var peerFingerprint: [MCPeerID: String] = [:]
    private var authenticated = Set<MCPeerID>()
    private var authorized = Set<MCPeerID>()
    private var ready = Set<MCPeerID>()
    private var cancellable: AnyCancellable?

    init(store: BookmarkStore) {
        self.store = store
        peerID = MCPeerID(displayName: DeviceIdentity.deviceName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["fp": DeviceIdentity.fingerprint],
            serviceType: PeerCoding.serviceType
        )
        super.init()
        session.delegate = self
        advertiser.delegate = self
    }

    @MainActor
    func start() {
        NSLog("Bookmarked sync fingerprint: \(DeviceIdentity.fingerprint)")
        advertiser.startAdvertisingPeer()
        SyncStatus.shared.setAdvertising(true)
        cancellable = store?.$items
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.pushDiff() }
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
                         deviceName: DeviceIdentity.deviceName),
             to: [peer])
    }

    @MainActor
    private func handle(_ message: PeerMessage, from peer: MCPeerID) {
        switch message.kind {
        case .hello: handleHello(message, from: peer)
        case .proof: handleProof(message, from: peer)
        case .manifest:
            guard ready.contains(peer) else { return }
            lastManifest = message.manifest ?? []
            pushDiff()
        case .push:
            break
        }
    }

    @MainActor
    private func handleHello(_ message: PeerMessage, from peer: MCPeerID) {
        guard let pk = message.publicKey, let theirNonce = message.nonce,
              let fp = message.fingerprint, fp == DeviceIdentity.fingerprint(for: pk) else {
            reject(peer); return
        }
        peerKey[peer] = pk
        peerFingerprint[peer] = fp

        if TrustStore.shared.isTrusted(fp) {
            guard TrustStore.shared.publicKey(for: fp) == pk else { reject(peer); return }
            authorized.insert(peer)
            replyProof(to: peer, theirNonce: theirNonce)
            maybeReady(peer)
            return
        }

        guard SyncCoordinator.shared.isPairing,
              let pairingNonce = SyncCoordinator.shared.pairingNonce,
              let pairingProof = message.pairingProof,
              DeviceIdentity.verify(pairingProof, of: pairingNonce, publicKey: pk) else {
            reject(peer); return
        }

        let name = message.deviceName ?? "iPhone"
        let sas = DeviceIdentity.shortAuthString(DeviceIdentity.publicKey, pk)
        replyProof(to: peer, theirNonce: theirNonce)
        SyncCoordinator.shared.requestConfirmation(
            .init(fingerprint: fp, name: name, sas: sas),
            confirm: { [weak self] in
                TrustStore.shared.add(TrustedPeer(fingerprint: fp, publicKey: pk, name: name, pairedAt: Date()))
                guard let self else { return }
                self.authorized.insert(peer)
                self.maybeReady(peer)
            },
            deny: { [weak self] in self?.reject(peer) }
        )
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
        publishPeerCount()
        pushDiff()
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
        if ready.isEmpty { lastManifest = [] }
        publishPeerCount()
    }

    @MainActor
    private func pushDiff() {
        guard let store else { return }
        let peers = session.connectedPeers.filter { ready.contains($0) }
        guard !peers.isEmpty else { return }
        let remote = Dictionary(lastManifest.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { a, _ in a })
        let items = store.items
        let upserts = items.filter { item in
            guard let theirs = remote[item.id] else { return true }
            return item.updatedAt > theirs
        }
        let localIDs = Set(items.map { $0.id })
        let deletes = lastManifest.map { $0.id }.filter { !localIDs.contains($0) }
        guard !upserts.isEmpty || !deletes.isEmpty else { return }
        send(PeerMessage(kind: .push, upserts: upserts, deletes: deletes), to: peers)
        SyncStatus.shared.markSynced()
    }

    @MainActor
    private func publishPeerCount() {
        SyncStatus.shared.setConnectedPeers(ready.count)
    }
}

extension PeerSync: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
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
