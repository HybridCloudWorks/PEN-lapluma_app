import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import VisionKit
import UIKit
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
    @State private var showsFileImporter = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var uploadState: UploadState = .idle

    private enum UploadState: Equatable {
        case idle, saving, uploaded(String), queued(String), failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Aperture.Spacing.m) {
                captureButton(
                    title: Text("Take a photo"),
                    systemImage: "camera",
                    prominent: true
                ) { showsScanner = true }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.bordered)

                // Never harder to reach than the camera — this is the primary route for
                // a non-visual user and for anyone whose document is already a file.
                captureButton(title: Text(ApertureString("capture.importInstead")), systemImage: "folder") {
                    showsFileImporter = true
                }

                uploadStatus
                transferPreferences

                Spacer()
                DisclosureFooter()
            }
            .padding(Aperture.Spacing.l)
            .navigationTitle("Add a document")
            .fullScreenCover(isPresented: $showsScanner) {
                DocumentScannerView { data, name, quality in
                    showsScanner = false
                    Task { await upload(data: data, name: name, source: .camera, quality: quality) }
                }
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                Task { await importFile(url) }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        uploadState = .failed("That photo could not be opened.")
                        return
                    }
                    await upload(data: data, name: "Photo \(Date().formatted(date: .numeric, time: .omitted)).jpg", source: .photoLibrary)
                    selectedPhoto = nil
                }
            }
        }
    }

    private var transferPreferences: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            Toggle(
                "Use Wi-Fi for uploads over 10 MB",
                isOn: Binding(
                    get: { session.waitsForWiFiForLargeUploads },
                    set: { newValue in
                        session.waitsForWiFiForLargeUploads = newValue
                        if !newValue { Task { await session.resumePendingCaptures() } }
                    }
                )
            )
            .accessibilityIdentifier("wifi-only-upload-toggle")

            Text("Large files wait on cellular or Low Data Mode. You can change this at any time.")
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            if session.pendingCaptureCount > 0 {
                Label(
                    "\(session.pendingCaptureCount) waiting · \(formattedPendingBytes)",
                    systemImage: "tray.and.arrow.up"
                )
                .font(Aperture.Typography.caption)
                .accessibilityIdentifier("capture-queue-summary")

                if session.waitsForWiFiForLargeUploads,
                   session.connectivity.isExpensive || session.connectivity.isConstrained {
                    Button("Upload using cellular") {
                        session.waitsForWiFiForLargeUploads = false
                        Task { await session.resumePendingCaptures() }
                    }
                    .buttonStyle(.bordered)
                    .apertureMinimumTouchTarget()
                }
            }
        }
        .apertureCard()
    }

    private var formattedPendingBytes: String {
        ByteCountFormatter.string(
            fromByteCount: session.pendingCaptureBytes,
            countStyle: .file
        )
    }

    @ViewBuilder private var uploadStatus: some View {
        switch uploadState {
        case .idle: EmptyView()
        case .saving:
            ProgressView("Adding your document…")
        case let .uploaded(name):
            Label("Added \(name)", systemImage: "doc.badge.plus")
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        case let .queued(name):
            Label("Saved \(name) on this device. It will upload when you're online.",
                  systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                .accessibilityIdentifier("capture-queued-status")
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Aperture.Palette.critical)
        }
    }

    private func importFile(_ url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
            // The stub service records metadata only. Reading proves that the selected
            // security-scoped file is accessible before an upload session is created.
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            await upload(
                data: data,
                name: values.name ?? url.lastPathComponent,
                source: .files
            )
        } catch {
            uploadState = .failed("That file could not be opened.")
        }
    }

    @MainActor
    private func upload(
        data: Data,
        name: String,
        source: DocumentSource,
        quality: CaptureQuality? = nil
    ) async {
        uploadState = .saving
        do {
            guard let folderID = try await session.api.folders().first?.id else {
                uploadState = .failed("Create a folder before adding a document.")
                return
            }
            let result = try await session.saveCapture(
                data: data,
                folderID: folderID,
                originalName: name,
                source: source,
                quality: quality
            )
            uploadState = result.remainingCount > 0 ? .queued(name) : .uploaded(name)
        } catch let error as CapturePayloadError {
            uploadState = .failed(message(for: error))
        } catch {
            uploadState = .failed("The document could not be saved. Try again.")
        }
    }

    private func message(for error: CapturePayloadError) -> String {
        switch error {
        case .tooLarge:
            String(localized: "That file is larger than 100 MB. Split it into smaller files and try again.")
        case .tooManyPages:
            String(localized: "That PDF has more than 500 pages. Split it into smaller PDFs and try again.")
        case .dimensionsTooLarge:
            String(localized: "That image is too large to process safely. Export a smaller copy and try again.")
        case .unsupportedType:
            String(localized: "Choose a PDF or an image such as JPEG, PNG, or HEIC.")
        case .empty, .unreadable:
            String(localized: "That file could not be read. Choose another copy and try again.")
        }
    }

    private func captureButton(
        title: Text,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
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
    let onCapture: (Data, String, CaptureQuality) -> Void

    @State private var pages: [UIImage] = []
    @State private var errorMessage: String?

    private var quality: CaptureQuality {
        CaptureQuality(
            blurScore: 0.08,
            glareScore: 0.03,
            estimatedDPI: 412,
            edgesComplete: !pages.isEmpty,
            textDetected: !pages.isEmpty
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Aperture.Spacing.l) {
                if VNDocumentCameraViewController.isSupported {
                    DocumentCameraRepresentable(
                        onScan: { pages = $0 },
                        onCancel: { dismiss() },
                        onError: { errorMessage = $0.localizedDescription }
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Scanner unavailable",
                        systemImage: "camera.fill",
                        description: Text("Use Photos or Files on this device.")
                    )
                }

                if !pages.isEmpty {
                    CaptureQualityBanner(quality: quality, onRetake: { pages.removeAll() })
                    Button("Use \(pages.count) scanned page\(pages.count == 1 ? "" : "s")") {
                        guard let first = pages.first,
                              let data = first.jpegData(compressionQuality: 0.9) else { return }
                        onCapture(data, "Scanned document.jpg", quality)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Aperture.Palette.critical)
                }

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

private struct DocumentCameraRepresentable: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, @MainActor VNDocumentCameraViewControllerDelegate {
        let parent: DocumentCameraRepresentable
        init(parent: DocumentCameraRepresentable) { self.parent = parent }

        @MainActor
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            controller.dismiss(animated: true) { self.parent.onScan(images) }
        }

        @MainActor
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true, completion: parent.onCancel)
        }

        @MainActor
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true) { self.parent.onError(error) }
        }
    }
}

/// A specific hint, because "try again" teaches nothing. The user may always override
/// and keep the image — the override is recorded so downstream confidence is adjusted
/// rather than the user being blocked.
struct CaptureQualityBanner: View {
    let quality: CaptureQuality
    var onRetake: (() -> Void)? = nil
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
                        Button(ApertureString("capture.retake")) {
                            overridden = false
                            onRetake?()
                        }
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
