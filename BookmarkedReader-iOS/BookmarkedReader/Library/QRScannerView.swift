import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var didScan = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.configure() }
            }
        }

        private func configure() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.layer.bounds
            view.layer.addSublayer(layer)
            preview = layer

            startSession()
        }

        private func startSession() {
            guard !session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.layer.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didScan,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let string = object.stringValue else { return }
            didScan = true
            session.stopRunning()
            onScan?(string)
        }
    }
}
