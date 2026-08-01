import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-07/S-08. The highest-leverage screen in the product.
///
/// The on-device quality gate runs **before upload** and returns a *specific* reason
/// within 800 ms, so the user re-shoots while the document is still in their hand
/// rather than discovering a failure hours later. A better photo beats a better model,
/// costs nothing at inference time, and fixes the problem at its source.
struct CaptureEntryView: View {
    @Environment(AppSession.self) private var session
    @State private var showsScanner = false
    @State private var showsPhotoPicker = false
    @State private var showsFileImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Aperture.Spacing.m) {
                captureButton(
                    title: "Take a photo",
                    systemImage: "camera",
                    prominent: true
                ) { showsScanner = true }

                captureButton(title: "Choose from Photos", systemImage: "photo.on.rectangle") {
                    showsPhotoPicker = true
                }

                // Never harder to reach than the camera — this is the primary route for
                // a non-visual user and for anyone whose document is already a file.
                captureButton(title: ApertureString("capture.importInstead"), systemImage: "folder") {
                    showsFileImporter = true
                }

                Spacer()
                DisclosureFooter()
            }
            .padding(Aperture.Spacing.l)
            .navigationTitle("Add a document")
            .sheet(isPresented: $showsScanner) { DocumentScannerView() }
        }
    }

    private func captureButton(
        title: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(prominent ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
    }
}

/// Type-erasing shim so the two branches above have the same type.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

/// Wraps `VNDocumentCameraViewController`. In the real client the per-frame quality
/// assessment runs on-device through the Vision framework; here the delegate surfaces
/// the same `CaptureQuality` shape so the review UI is exercised identically.
struct DocumentScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var simulatedQuality = CaptureQuality(
        blurScore: 0.08, glareScore: 0.03, estimatedDPI: 412,
        edgesComplete: false, textDetected: true
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: Aperture.Spacing.l) {
                RoundedRectangle(cornerRadius: Aperture.Radius.card)
                    .fill(Aperture.Palette.surfaceSecondary)
                    .overlay {
                        Text("Camera preview\n(VNDocumentCameraViewController)")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                    .frame(height: 360)
                    .accessibilityLabel("Camera viewfinder")
                    .accessibilityHint("Point the camera at your document. I'll tell you when the framing is right.")

                CaptureQualityBanner(quality: simulatedQuality)

                Spacer()
            }
            .padding(Aperture.Spacing.l)
            .navigationTitle("Scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ApertureString("common.cancel")) { dismiss() }
                }
            }
        }
    }
}

/// A specific hint, because "try again" teaches nothing. The user may always override
/// and keep the image — the override is recorded so downstream confidence is adjusted
/// rather than the user being blocked.
struct CaptureQualityBanner: View {
    let quality: CaptureQuality
    @State private var overridden = false

    var body: some View {
        Group {
            if let issue = quality.issue, !overridden {
                VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                    Label(ApertureString(String.LocalizationValue(issue.hintKey)),
                          systemImage: "exclamationmark.circle")
                        .font(Aperture.Typography.body)
                        .foregroundStyle(Aperture.Palette.warning)

                    HStack {
                        Button(ApertureString("capture.retake")) {}
                            .buttonStyle(.borderedProminent)
                        Button(ApertureString("capture.keepAnyway")) { overridden = true }
                    }
                }
                .apertureCard()
                // Announced immediately so a VoiceOver user gets the hint at the moment
                // it matters, not when they next swipe.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            } else {
                Label("Looks good", systemImage: "checkmark.circle")
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }
        }
    }
}
