import Foundation
import CoreGraphics

/// Encodes one camera scan as one PDF while preserving every page, its order, and
/// its dimensions. The core is pure CoreGraphics so `swift test` proves the
/// all-pages guarantee on any platform; the app target adds a thin `UIImage`
/// entry point that applies orientation before handing pages here.
public enum ScannedDocumentEncoder {
    public enum EncodingError: Error { case noPages, invalidPageSize, contextUnavailable }

    public struct Page {
        public let image: CGImage
        /// PDF page bounds in points. Pixel dimensions may be a scale multiple of
        /// this — a 2x scan of a 100-point-wide page still yields a 100-point page,
        /// exactly as the UIKit renderer produced before.
        public let size: CGSize

        public init(image: CGImage, size: CGSize) {
            self.image = image
            self.size = size
        }
    }

    public static func pdfData(pages: [Page]) throws -> Data {
        guard !pages.isEmpty else { throw EncodingError.noPages }
        guard pages.allSatisfy({ $0.size.width > 0 && $0.size.height > 0 }) else {
            throw EncodingError.invalidPageSize
        }

        let output = NSMutableData()
        var firstPageBounds = CGRect(origin: .zero, size: pages[0].size)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &firstPageBounds, nil) else {
            throw EncodingError.contextUnavailable
        }

        for page in pages {
            var bounds = CGRect(origin: .zero, size: page.size)
            let pageInfo = [
                kCGPDFContextMediaBox as String: NSData(
                    bytes: &bounds,
                    length: MemoryLayout<CGRect>.size
                )
            ] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.draw(page.image, in: bounds)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }
}
