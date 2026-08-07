import Foundation
import CoreImage
import CryptoKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public struct PreparedCapturePayload: Sendable {
    public let data: Data
    public let contentSHA256: String
    public let verifiedMIMEType: String
    public let pageCount: Int
    public let strippedImageMetadata: Bool
}

public enum CapturePayloadError: Error, Sendable, Equatable {
    case empty
    case tooLarge(maxBytes: Int)
    case tooManyPages(maxPages: Int)
    case dimensionsTooLarge(maxPixels: Int)
    case unsupportedType
    case unreadable
}

/// On-device privacy and validation gate shared by every capture entry point.
/// Imported images are decoded, oriented from their EXIF value, and re-encoded with
/// no source property dictionaries, which removes GPS and all other EXIF metadata.
public enum CapturePayloadProcessor {
    public static let maximumBytes = 100 * 1_024 * 1_024
    public static let maximumPDFPages = 500
    public static let maximumImageDimension = 10_000

    public static func prepare(_ input: Data) throws -> PreparedCapturePayload {
        try validateByteCount(input.count)

        if input.starts(with: [0x25, 0x50, 0x44, 0x46]) { // %PDF
            return try preparePDF(input)
        }
        return try prepareImage(input)
    }

    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func validateByteCount(_ count: Int) throws {
        guard count > 0 else { throw CapturePayloadError.empty }
        guard count <= maximumBytes else {
            throw CapturePayloadError.tooLarge(maxBytes: maximumBytes)
        }
    }

    public static func validatePDFPageCount(_ count: Int) throws {
        guard count > 0 else { throw CapturePayloadError.unreadable }
        guard count <= maximumPDFPages else {
            throw CapturePayloadError.tooManyPages(maxPages: maximumPDFPages)
        }
    }

    private static func preparePDF(_ data: Data) throws -> PreparedCapturePayload {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw CapturePayloadError.unreadable
        }
        try validatePDFPageCount(document.pageCount)
        return PreparedCapturePayload(
            data: data,
            contentSHA256: sha256(of: data),
            verifiedMIMEType: UTType.pdf.preferredMIMEType ?? "application/pdf",
            pageCount: document.pageCount,
            strippedImageMetadata: false
        )
    }

    private static func prepareImage(_ data: Data) throws -> PreparedCapturePayload {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw CapturePayloadError.unsupportedType
        }
        guard width <= maximumImageDimension, height <= maximumImageDimension else {
            throw CapturePayloadError.dimensionsTooLarge(maxPixels: maximumImageDimension)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CapturePayloadError.unreadable
        }

        let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        // ImageIO metadata is untrusted input. CIImage accepts the eight TIFF/EXIF
        // orientation values; validating before conversion also prevents a trapping
        // UInt32-to-Int32 conversion for malformed metadata.
        let safeOrientation: Int32 = (1...8).contains(rawOrientation)
            ? Int32(rawOrientation)
            : 1
        let oriented = CIImage(cgImage: image).oriented(forExifOrientation: safeOrientation)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let normalized = context.createCGImage(oriented, from: oriented.extent) else {
            throw CapturePayloadError.unreadable
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CapturePayloadError.unreadable
        }
        // Supplying only encoding quality is intentional: no source EXIF, GPS, TIFF,
        // IPTC, thumbnail, or other source metadata crosses this boundary. ImageIO may
        // synthesize non-sensitive pixel-dimension fields required by the output codec.
        CGImageDestinationAddImage(
            destination,
            normalized,
            [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CapturePayloadError.unreadable
        }

        let prepared = output as Data
        guard prepared.count <= maximumBytes else {
            throw CapturePayloadError.tooLarge(maxBytes: maximumBytes)
        }
        return PreparedCapturePayload(
            data: prepared,
            contentSHA256: sha256(of: prepared),
            verifiedMIMEType: UTType.jpeg.preferredMIMEType ?? "image/jpeg",
            pageCount: 1,
            strippedImageMetadata: true
        )
    }
}
