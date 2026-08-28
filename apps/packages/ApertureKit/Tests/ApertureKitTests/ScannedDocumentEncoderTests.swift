import Foundation
import CoreGraphics
import Testing
import ApertureAPI

/// The all-pages guarantee at package speed: what
/// `testMultiPageScanEncoderPreservesPageCountOrderAndDimensions` proves through
/// the simulator, these prove in `swift test` on every pull request.
@Suite("Scanned document encoder")
struct ScannedDocumentEncoderTests {

    private func makeImage(width: Int, height: Int, gray: CGFloat = 0.5) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func mediaBoxes(of data: Data) throws -> [CGSize] {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        return (1...document.numberOfPages).compactMap { number in
            document.page(at: number)?.getBoxRect(.mediaBox).size
        }
    }

    @Test("Every page survives with its order and point dimensions")
    func pagesSurviveWithOrderAndDimensions() throws {
        let sizes = [CGSize(width: 100, height: 120),
                     CGSize(width: 200, height: 140),
                     CGSize(width: 300, height: 160)]
        let pages = try sizes.map { size in
            ScannedDocumentEncoder.Page(
                image: try makeImage(width: Int(size.width), height: Int(size.height)),
                size: size
            )
        }
        let data = try ScannedDocumentEncoder.pdfData(pages: pages)
        #expect(try mediaBoxes(of: data) == sizes)
    }

    @Test("A 2x capture yields a page in points, not pixels")
    func scaledPixelsKeepPointBounds() throws {
        let page = ScannedDocumentEncoder.Page(
            image: try makeImage(width: 200, height: 240),
            size: CGSize(width: 100, height: 120)
        )
        let data = try ScannedDocumentEncoder.pdfData(pages: [page])
        #expect(try mediaBoxes(of: data) == [CGSize(width: 100, height: 120)])
    }

    @Test("Empty and degenerate inputs fail closed")
    func emptyAndDegenerateInputsFailClosed() throws {
        #expect(throws: ScannedDocumentEncoder.EncodingError.noPages) {
            _ = try ScannedDocumentEncoder.pdfData(pages: [])
        }
        let zero = ScannedDocumentEncoder.Page(
            image: try makeImage(width: 10, height: 10),
            size: .zero
        )
        #expect(throws: ScannedDocumentEncoder.EncodingError.invalidPageSize) {
            _ = try ScannedDocumentEncoder.pdfData(pages: [zero])
        }
    }
}
