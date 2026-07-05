import SwiftUI
import VisionKit

/// `UIViewControllerRepresentable` wrapping VisionKit's `DataScannerViewController`
/// for live barcode scanning. On the FIRST recognized barcode it invokes `onScan`
/// with the payload string and dismisses; a parse/scan failure leaves the camera
/// running so the user can retry.
///
/// AVAILABILITY: the scanner needs a real camera + Neural Engine, so it is NOT
/// available in the simulator. The presenting view MUST gate on
/// `BarcodeScannerView.isScanningAvailable` and render a graceful fallback
/// (rather than presenting a black screen) when it's false.
struct BarcodeScannerView: UIViewControllerRepresentable {
    /// Called with the recognized barcode payload string. The presenter handles
    /// the OFF lookup + add-flow prefill.
    let onScan: (String) -> Void
    /// Called once after a scan so the presenter can dismiss the sheet.
    var onDismiss: () -> Void = {}

    /// Whether live barcode scanning can run on THIS device right now: the
    /// hardware/OS supports `DataScannerViewController` AND it is currently
    /// available (camera present + not restricted). False on the simulator, so
    /// the entry point can disable the affordance instead of crashing.
    static var isScanningAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        // Idempotent start — `try?` swallows the "already scanning"/unavailable
        // throw so a SwiftUI update never crashes (availability is gated upstream).
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    /// Bridges the VisionKit delegate callbacks to the SwiftUI closures. Fires
    /// `onScan` + `onDismiss` exactly once (the `hasScanned` latch guards against
    /// a second recognized item racing in before the sheet dismisses).
    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let onDismiss: () -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
            self.onScan = onScan
            self.onDismiss = onDismiss
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            handle(addedItems, scanner: dataScanner)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            handle([item], scanner: dataScanner)
        }

        private func handle(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !hasScanned else { return }
            for item in items {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue?.trimmed,
                   !payload.isEmpty {
                    hasScanned = true
                    scanner.stopScanning()
                    onScan(payload)
                    onDismiss()
                    return
                }
            }
        }
    }
}

/// Presented entry point for the scanner: a full-screen camera with a 取消 button
/// + scrim hint, OR a graceful "此设备不支持扫码" fallback when the device can't
/// scan (e.g. the simulator) — never a black screen. The caller presents this in
/// a `fullScreenCover`; `onScan` fires once and the screen self-dismisses.
struct BarcodeScannerScreen: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if BarcodeScannerView.isScanningAvailable {
                BarcodeScannerView(
                    onScan: { code in
                        onScan(code)
                        dismiss()
                    },
                    onDismiss: { dismiss() }
                )
                .ignoresSafeArea()
                scanHint
            } else {
                unavailable
            }
            cancelBar
        }
        .background(Color.black)
    }

    private var scanHint: some View {
        VStack {
            Spacer()
            Text(String(localized: "inventory.scan.hint"))
                .font(.fkLabelLarge)
                .foregroundStyle(.white)
                .padding(.horizontal, FkSpacing.lg)
                .padding(.vertical, FkSpacing.md)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(.bottom, FkSpacing.xxl)
        }
    }

    private var unavailable: some View {
        VStack(spacing: FkSpacing.md) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(String(localized: "inventory.scan.deviceUnsupported"))
                .font(.fkTitleMedium)
                .foregroundStyle(.white)
            Text(String(localized: "inventory.scan.useRealDevice"))
                .font(.fkBodyMedium)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(FkSpacing.xl)
    }

    private var cancelBar: some View {
        VStack {
            HStack {
                Spacer()
                Button(String(localized: "inventory.action.cancel")) { dismiss() }
                    .font(.fkLabelLarge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, FkSpacing.md)
                    .padding(.vertical, FkSpacing.sm)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
            }
            .padding(FkSpacing.lg)
            Spacer()
        }
    }
}
