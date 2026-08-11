import CoreGraphics
import CoreText
import Foundation
import ApertureDomain

/// Builds a real, printable PDF for the local-only fixture. The pages are clearly
/// marked as demo output so simulator testing can exercise Files and AirPrint without
/// manufacturing official government forms or implying that the fixture is fileable.
enum StubPackageArtifactFactory {
    static func make(for package: GeneratedPackage) throws -> PackageArtifact {
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else {
            throw artifactError()
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let metadata = [
            kCGPDFContextTitle as String: "LaPluma internal demo package",
            kCGPDFContextCreator as String: "LaPluma local fixture"
        ] as CFDictionary
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata) else {
            throw artifactError()
        }

        var renderedPageCount = 0
        for output in package.outputs.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            for pageNumber in 1...max(output.pageCount, 1) {
                context.beginPDFPage(nil)
                draw(
                    "INTERNAL DEMO — NOT FOR FILING",
                    at: CGPoint(x: 54, y: 720),
                    size: 16,
                    weight: "Helvetica-Bold",
                    context: context
                )
                draw(
                    output.formNumber ?? output.kind.rawValue.replacingOccurrences(of: "_", with: " "),
                    at: CGPoint(x: 54, y: 670),
                    size: 22,
                    weight: "Helvetica-Bold",
                    context: context
                )
                draw(
                    "Fixture output \(output.id) — page \(pageNumber) of \(max(output.pageCount, 1))",
                    at: CGPoint(x: 54, y: 635),
                    size: 12,
                    weight: "Helvetica",
                    context: context
                )
                draw(
                    "This PDF exists only to verify package export and printing in the local Alpha 0.2 build.",
                    at: CGPoint(x: 54, y: 600),
                    size: 10,
                    weight: "Helvetica",
                    context: context
                )
                context.endPDFPage()
                renderedPageCount += 1
            }
        }
        context.closePDF()

        let data = mutableData as Data
        guard renderedPageCount > 0, data.starts(with: [0x25, 0x50, 0x44, 0x46]) else {
            throw artifactError()
        }
        let safeID = package.id.rawValue.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : "-"
        }
        return PackageArtifact(
            fileName: "LaPluma-Package-\(String(safeID)).pdf",
            mimeType: "application/pdf",
            pageCount: renderedPageCount,
            contentSHA256: CapturePayloadProcessor.sha256(of: data),
            data: data
        )
    }

    private static func draw(
        _ text: String,
        at position: CGPoint,
        size: CGFloat,
        weight: String,
        context: CGContext
    ) {
        let font = CTFontCreateWithName(weight as CFString, size, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0.12, alpha: 1)
        ] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else {
            return
        }
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = position
        CTLineDraw(line, context)
    }

    private static func artifactError() -> ProblemDetails {
        ProblemDetails(
            type: "https://api.aperture.app/problems/package-artifact-unavailable",
            title: "The generated package could not be prepared",
            status: 500
        )
    }
}
