import Foundation
import Combine

@MainActor
final class SyncStatus: ObservableObject {
    static let shared = SyncStatus()

    @Published private(set) var isAdvertising = false
    @Published private(set) var connectedPeers = 0
    @Published private(set) var lastSyncedAt: Date?

    private init() {}

    func setAdvertising(_ on: Bool) { isAdvertising = on }

    func setConnectedPeers(_ count: Int) { connectedPeers = count }

    func markSynced() { lastSyncedAt = Date() }
}
