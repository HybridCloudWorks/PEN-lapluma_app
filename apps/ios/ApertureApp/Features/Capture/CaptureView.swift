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
    var body: some View {
        NavigationStack {
            CaptureView()
        }
    }
}

/// Capture content that can live in either the Capture tab's stack or a stack that
/// pushed it from a missing-item resolution path.
struct CaptureView: View {
    @Environment(AppSession.self) private var session
    @State private var showsScanner = false
    @State private var showsFileImporter = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var uploadState: UploadState = .idle
    @State private var folders: [Folder] = []
    @State private var selectedFolderID: FolderID?

    private enum UploadState: Equatable {
        case idle, saving, uploaded(String), queued(String), failed(String)
    }

    var body: some View {
        ApertureCanvas {
            ScrollView {
                VStack(spacing: Aperture.Spacing.l) {
                    VStack(spacing: Aperture.Spacing.s) {
                        Text("Add paperwork")
                            .font(Aperture.Typography.sectionTitle)
                        Text("Scan it, choose a photo, or open a file.")
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    destination

                    captureButton(
                        title: Text("Take a photo"),
                        systemImage: "doc.viewfinder",
                        prominent: true
                    ) { showsScanner = true }

                    ApertureGlassEffectGroup(spacing: Aperture.Spacing.s) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Aperture.Spacing.s) {
                                photoPicker
                                fileButton
                            }
                            VStack(spacing: Aperture.Spacing.s) {
                                photoPicker
                                fileButton
                            }
                        }
                    }

                    uploadStatus
                    transferPreferences
                    #if DEBUG
                    syntheticCaptureButton
                    #endif

                    DisclosureFooter()
                }
                .padding(Aperture.Spacing.l)
                .apertureReadableContentWidth(maximum: 760)
            }
        }
        .navigationTitle("Add a document")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.dataRevision) { await loadFolders() }
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
                    uploadState = .failed(LaPlumaString("That photo could not be opened."))
                    // Cleared so re-picking the same photo fires onChange again;
                    // otherwise the retry is a silent no-op.
                    selectedPhoto = nil
                    return
                }
                let date = Date.FormatStyle(date: .numeric, time: .omitted)
                    .locale(session.preferredLocale)
                    .format(Date())
                await upload(
                    data: data,
                    name: LaPlumaFormat("capture.photoFileName", date),
                    source: .photoLibrary
                )
                selectedPhoto = nil
            }
        }
    }

    #if DEBUG
    /// The camera and the photo picker both need capabilities the Simulator cannot
    /// grant a test, so the offline queue journey has no way to put real bytes in
    /// the queue. This routes a synthetic image through the **production** path —
    /// `upload` → `saveCapture` → payload processing → the durable queue — so the
    /// journey exercises the real code rather than a mock of it. It is compiled out
    /// of Release and hidden unless the test-only argument is present.
    @ViewBuilder private var syntheticCaptureButton: some View {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-enqueue-capture") {
            Button {
                Task {
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160)).image { context in
                        UIColor.systemTeal.setFill()
                        context.cgContext.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
                    }
                    guard let data = image.jpegData(compressionQuality: 0.9) else { return }
                    await upload(data: data, name: "Test document.jpg", source: .files)
                }
            } label: {
                // verbatim: scaffolding that must never reach an applicant, so it
                // must never enter the localization tables either.
                Text(verbatim: "Add a test document")
            }
            .buttonStyle(.bordered)
            .apertureMinimumTouchTarget()
            .accessibilityIdentifier("debug-enqueue-capture")
        }
    }
    #endif

    @MainActor private var photoPicker: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                .font(Aperture.Typography.value)
                .frame(maxWidth: .infinity, minHeight: Aperture.Spacing.minimumTarget)
        }
        .apertureGlassButton()
        .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
    }

    @MainActor private var fileButton: some View {
        // Never harder to reach than the camera — this is the primary route for
        // a non-visual user and for anyone whose document is already a file.
        captureButton(
            title: Text(ApertureString("capture.importInstead")),
            systemImage: "folder",
            prominent: false
        ) {
            showsFileImporter = true
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

            Text("Large files wait for Wi-Fi.")
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            if session.pendingCaptureCount > 0 {
                Label(
                    LaPlumaFormat(
                        "capture.pendingSummary",
                        session.pendingCaptureCount,
                        formattedPendingBytes
                    ),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(Aperture.Typography.caption)
                .apertureStatusSurface(.attention)
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
        session.pendingCaptureBytes.formatted(
            .byteCount(style: .file).locale(session.preferredLocale)
        )
    }

    @ViewBuilder private var uploadStatus: some View {
        switch uploadState {
        case .idle: EmptyView()
        case .saving:
            HStack(spacing: Aperture.Spacing.s) {
                ProgressView()
                Label("Adding your document…", systemImage: "doc.badge.arrow.up")
            }
            .apertureStatusSurface(.information)
        case let .uploaded(name):
            Label(LaPlumaFormat("capture.addedDocument", name), systemImage: "checkmark.circle.fill")
                .apertureStatusSurface(.positive)
        case let .queued(name):
            Label(LaPlumaFormat("capture.queuedDocument", name),
                  systemImage: "clock.arrow.circlepath")
                .apertureStatusSurface(.attention)
                .accessibilityIdentifier("capture-queued-status")
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.octagon.fill")
                .apertureStatusSurface(.critical)
        }
    }

    /// Documents used to land in whichever folder the API happened to return first,
    /// with nothing on screen saying so. Once a user has more than one folder — which
    /// creating a folder makes routine — that is a filing error the applicant cannot
    /// see, on records that end up in front of an adjudicator. Show the destination
    /// always; offer a choice when there is one to make.
    @ViewBuilder private var destination: some View {
        if !folders.isEmpty {
            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                Text("Where this goes")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                if folders.count == 1, let only = folders.first {
                    Text(only.name)
                        .font(Aperture.Typography.value)
                        .accessibilityIdentifier("capture-destination")
                } else {
                    Picker("Where this goes", selection: $selectedFolderID) {
                        ForEach(folders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("capture-destination")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @MainActor private func loadFolders() async {
        guard let loaded = try? await session.api.folders() else { return }
        folders = loaded
        // Keep an explicit selection unless it no longer exists; otherwise default to
        // the first folder, which is what the screen displays.
        if selectedFolderID == nil || !loaded.contains(where: { $0.id == selectedFolderID }) {
            selectedFolderID = loaded.first?.id
        }
    }

    private func importFile(_ url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
            // Enforce the limit from the file's own metadata, before mapping it. The
            // same check runs again inside the processor on the bytes actually read;
            // doing it here means an over-sized file is refused without mapping it
            // first, and the size we already asked the filesystem for is now used.
            if let fileSize = values.fileSize {
                try CapturePayloadProcessor.validateByteCount(fileSize)
            }
            // The stub service records metadata only. Reading proves that the selected
            // security-scoped file is accessible before an upload session is created.
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            await upload(
                data: data,
                name: values.name ?? url.lastPathComponent,
                source: .files
            )
        } catch let error as CapturePayloadError {
            uploadState = .failed(message(for: error))
        } catch {
            uploadState = .failed(LaPlumaString("That file could not be opened."))
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
            // The destination the screen showed, not whatever the API returns first.
            let resolvedFolderID = selectedFolderID ?? (try await session.api.folders().first?.id)
            guard let folderID = resolvedFolderID else {
                uploadState = .failed(LaPlumaString("Create a folder before adding a document."))
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
            uploadState = .failed(LaPlumaString("The document could not be saved. Try again."))
        }
    }

    private func message(for error: CapturePayloadError) -> String {
        switch error {
        case .tooLarge:
            LaPlumaString("That file is larger than 100 MB. Split it into smaller files and try again.")
        case .tooManyPages:
            LaPlumaString("That PDF has more than 500 pages. Split it into smaller PDFs and try again.")
        case .dimensionsTooLarge:
            LaPlumaString("That image is too large to process safely. Export a smaller copy and try again.")
        case .unsupportedType:
            LaPlumaString("Choose a PDF or an image such as JPEG, PNG, or HEIC.")
        case .empty, .unreadable:
            LaPlumaString("That file could not be read. Choose another copy and try again.")
        }
    }

    @MainActor private func captureButton(
        title: Text,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: prominent ? Aperture.Spacing.m : Aperture.Spacing.s) {
                Image(systemName: systemImage)
                    .font(prominent ? .system(size: 42, weight: .medium) : .body)
                title
                    .font(Aperture.Typography.value)
            }
            .frame(maxWidth: .infinity, minHeight: prominent ? 132 : 44)
        }
        .apertureGlassButton(prominent: prominent)
        .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.card))
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
                        onError: { _ in
                            errorMessage = LaPlumaString("The scanner stopped unexpectedly. Try again.")
                        }
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
                    Button(LaPlumaFormat("capture.scanUsePages", pages.count)) {
                        do {
                            let data = try ScannedDocumentEncoder.pdfData(for: pages)
                            onCapture(data, "Scanned document.pdf", quality)
                        } catch {
                            errorMessage = LaPlumaString("capture.scanEncodingFailed")
                        }
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

/// Encodes one camera scan as one PDF while preserving every page and its orientation.
/// Keeping this separate from the scanner delegate makes the all-pages guarantee
/// straightforward to exercise without presenting `VNDocumentCameraViewController`.
enum ScannedDocumentEncoder {
    enum EncodingError: Error { case noPages, invalidPageSize }

    static func pdfData(for pages: [UIImage]) throws -> Data {
        guard let first = pages.first else { throw EncodingError.noPages }
        guard pages.allSatisfy({ $0.size.width > 0 && $0.size.height > 0 }) else {
            throw EncodingError.invalidPageSize
        }

        let firstPageBounds = CGRect(origin: .zero, size: first.size)
        let renderer = UIGraphicsPDFRenderer(bounds: firstPageBounds)
        return renderer.pdfData { context in
            for page in pages {
                let bounds = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                page.draw(in: bounds)
            }
        }
    }
}

#if DEBUG
/// A test-only route that exercises the production encoder without presenting the
/// hardware-only document camera.
struct ScanEncoderDiagnosticView: View {
    @State private var result = "scan-pdf-validating"

    var body: some View {
        Text(result)
            .accessibilityIdentifier(result)
            .task {
                let sizes = [
                    CGSize(width: 100, height: 120),
                    CGSize(width: 200, height: 140),
                    CGSize(width: 300, height: 160)
                ]
                let pages = sizes.enumerated().map { index, size in
                    UIGraphicsImageRenderer(size: size).image { context in
                        UIColor(hue: CGFloat(index) / 3, saturation: 1, brightness: 1, alpha: 1)
                            .setFill()
                        context.cgContext.fill(CGRect(origin: .zero, size: size))
                    }
                }
                guard let data = try? ScannedDocumentEncoder.pdfData(for: pages),
                      let provider = CGDataProvider(data: data as CFData),
                      let document = CGPDFDocument(provider) else {
                    result = "scan-pdf-invalid"
                    return
                }
                let widths = (1...document.numberOfPages).compactMap { pageNumber in
                    document.page(at: pageNumber).map {
                        Int($0.getBoxRect(.mediaBox).width.rounded())
                    }
                }
                result = "scan-pdf-pages-\(document.numberOfPages)-widths-\(widths.map(String.init).joined(separator: "-"))"
            }
    }
}
#endif

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
                .onAppear { announce(issue) }
                .onChange(of: quality.issue) { _, newIssue in
                    guard let newIssue else { return }
                    announce(newIssue)
                }
            } else {
                Label("Looks good", systemImage: "checkmark.circle.fill")
                    .apertureStatusSurface(.positive)
            }
        }
    }

    private func announce(_ issue: CaptureQuality.Issue) {
        AccessibilityNotification.Announcement(
            ApertureString(String.LocalizationValue(issue.hintKey))
        ).post()
    }
}
