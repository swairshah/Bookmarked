import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

struct SyncSettingsPane: View {
    @ObservedObject private var status = SyncStatus.shared
    @ObservedObject private var coordinator = SyncCoordinator.shared
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                thisMac
                pairedDevices
                statusSection
            }
            .padding(18)
        }
        .sheet(isPresented: $showAdd, onDismiss: { coordinator.endPairing() }) {
            AddDeviceSheet()
        }
    }

    private var thisMac: some View {
        section("This Mac") {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DeviceIdentity.deviceName).font(.system(size: 13, weight: .medium))
                    Text("ID \(DeviceIdentity.fingerprint)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    private var pairedDevices: some View {
        section("Paired devices") {
            if coordinator.trusted.isEmpty {
                Text("No devices paired yet. Add your iPhone to sync your library over the local network.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(coordinator.trusted) { peer in
                        HStack(spacing: 10) {
                            Image(systemName: "iphone").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.name).font(.system(size: 13, weight: .medium))
                                Text("paired \(peer.pairedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Unpair") { coordinator.unpair(peer.fingerprint) }
                                .controlSize(.small)
                        }
                        .padding(.vertical, 7)
                        if peer.id != coordinator.trusted.last?.id { Divider() }
                    }
                }
            }

            Button {
                coordinator.beginPairing()
                showAdd = true
            } label: {
                Label("Add iPhone…", systemImage: "qrcode")
            }
            .controlSize(.large)
        }
    }

    private var statusSection: some View {
        section("Status") {
            row(status.isAdvertising ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                status.isAdvertising ? .green : .secondary,
                status.isAdvertising ? "Advertising on the local network" : "Not advertising")
            row(status.connectedPeers > 0 ? "iphone" : "iphone.slash",
                status.connectedPeers > 0 ? .green : .secondary,
                status.connectedPeers > 0
                    ? "\(status.connectedPeers) device\(status.connectedPeers == 1 ? "" : "s") connected"
                    : "No devices connected")
            if let date = status.lastSyncedAt {
                row("checkmark.circle", .secondary, "Last pushed \(date.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ icon: String, _ tint: Color, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 20)
            Text(title).font(.system(size: 13))
            Spacer()
        }
    }
}

private struct AddDeviceSheet: View {
    @ObservedObject private var coordinator = SyncCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            if let pending = coordinator.pending {
                confirm(pending)
            } else {
                qr
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { if coordinator.pairingNonce == nil { coordinator.beginPairing() } }
    }

    private var qr: some View {
        VStack(spacing: 14) {
            Text("Add iPhone").font(.system(size: 16, weight: .semibold))
            if let image = Self.qrImage(coordinator.pairingPayloadJSON) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text("In Bookmarked Reader on your iPhone, tap the sync button and scan this code.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel") { dismiss() }
        }
    }

    private func confirm(_ pending: SyncCoordinator.PendingPairing) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Pair “\(pending.name)”?").font(.system(size: 16, weight: .semibold))
            Text("Confirm this code matches the one shown on your iPhone:")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(pending.sas)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .tracking(6)
            HStack(spacing: 12) {
                Button("Don’t Pair", role: .cancel) { coordinator.deny() }
                Button("Pair") {
                    coordinator.confirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    static func qrImage(_ string: String) -> NSImage? {
        guard !string.isEmpty else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
