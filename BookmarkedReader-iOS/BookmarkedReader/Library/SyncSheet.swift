import SwiftUI

struct SyncSheet: View {
    @ObservedObject var store: BookmarkStore
    @ObservedObject private var pairing = PairingController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingScanner = false
    @State private var scanError: String?

    var body: some View {
        NavigationStack {
            List {
                if let code = pairing.verificationCode, pairing.pendingFingerprint != nil {
                    Section {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Verify this code matches your Mac")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(code)
                                .font(.system(size: 30, weight: .bold, design: .monospaced))
                                .tracking(6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                Section("This iPhone") {
                    LabeledContent(DeviceIdentity.deviceName, value: DeviceIdentity.fingerprint)
                        .font(.system(.body, design: .default))
                }

                Section("Paired Macs") {
                    if pairing.trusted.isEmpty {
                        Text("No Macs paired yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pairing.trusted) { peer in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.name)
                                Text("paired \(peer.pairedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { pairing.trusted[$0].fingerprint }.forEach(pairing.unpair)
                            store.restartPeerSync()
                        }
                    }

                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan Mac QR Code", systemImage: "qrcode.viewfinder")
                    }
                }

                Section("Status") {
                    Label(pairing.connectedPeers > 0 ? "Connected" : "Not connected",
                          systemImage: pairing.connectedPeers > 0 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(pairing.connectedPeers > 0 ? .green : .secondary)
                    if let date = pairing.lastSyncedAt {
                        LabeledContent("Last synced", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            .navigationTitle("Local Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingScanner) {
                scannerSheet
            }
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            QRScannerView { scanned in
                guard let payload = PairingPayload.parse(scanned), payload.v == 2 else {
                    scanError = "That QR code isn’t a Bookmarked pairing code."
                    return
                }
                pairing.beginPairing(payload)
                store.restartPeerSync()
                showingScanner = false
            }
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text("Point at the QR code in Bookmarked → Settings → Sync on your Mac.")
                    .font(.footnote)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showingScanner = false }
                }
            }
            .alert("Scan Failed", isPresented: Binding(
                get: { scanError != nil },
                set: { if !$0 { scanError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanError ?? "")
            }
        }
    }
}
