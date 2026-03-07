import ARKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PersistedFrameAssets {
    let imagePath: String
    let depthPath: String?
    let confidenceMapPath: String?
}

final class FrameBundleWriter {
    enum WriterError: LocalizedError {
        case imageEncodingFailed
        case destinationCreationFailed
        case pixelBufferUnsupported
        case pixelBufferBaseAddressUnavailable
        case cgImageCreationFailed

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed:
                return "Failed to finalize the image destination while writing a captured frame."
            case .destinationCreationFailed:
                return "Failed to create an image destination for the captured frame."
            case .pixelBufferUnsupported:
                return "Encountered an unsupported pixel buffer format while writing frame assets."
            case .pixelBufferBaseAddressUnavailable:
                return "Could not access the underlying pixel buffer bytes."
            case .cgImageCreationFailed:
                return "Could not create a CGImage from the captured pixel buffer."
            }
        }
    }

    private let ciContext = CIContext()

    func writeFrameAssets(
        frame: ARFrame,
        roomID: UUID,
        sessionID: UUID,
        frameID: UUID,
        persistence: RoomPersistenceService
    ) throws -> PersistedFrameAssets {
        try persistence.createFrameBundleDirectory(roomID: roomID, sessionID: sessionID)

        let imageURL = persistence.frameImageURL(roomID: roomID, sessionID: sessionID, frameID: frameID)
        try writeJPEG(from: frame.capturedImage, to: imageURL)

        var depthPath: String?
        var confidenceMapPath: String?
        if let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            let depthURL = persistence.frameDepthURL(roomID: roomID, sessionID: sessionID, frameID: frameID)
            try writeDepthPNG(from: sceneDepth.depthMap, to: depthURL)
            depthPath = depthURL.path

            if let confidenceBuffer = sceneDepth.confidenceMap {
                let confidenceURL = persistence.frameConfidenceURL(
                    roomID: roomID,
                    sessionID: sessionID,
                    frameID: frameID
                )
                try writeConfidencePNG(from: confidenceBuffer, to: confidenceURL)
                confidenceMapPath = confidenceURL.path
            }
        }

        return PersistedFrameAssets(
            imagePath: imageURL.path,
            depthPath: depthPath,
            confidenceMapPath: confidenceMapPath
        )
    }

    private func writeJPEG(from pixelBuffer: CVPixelBuffer, to url: URL) throws {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw WriterError.cgImageCreationFailed
        }
        try writeCGImage(
            cgImage,
            to: url,
            typeIdentifier: UTType.jpeg.identifier,
            properties: [
                kCGImageDestinationLossyCompressionQuality: 0.92,
            ]
        )
    }

    private func writeDepthPNG(from pixelBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw WriterError.pixelBufferBaseAddressUnavailable
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = width * MemoryLayout<UInt16>.size
        var millimeterDepth = Data(count: height * bytesPerRow)

        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_OneComponent32Float:
            let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer) / MemoryLayout<Float32>.size
            millimeterDepth.withUnsafeMutableBytes { destinationBytes in
                guard let destination = destinationBytes.baseAddress?.assumingMemoryBound(to: UInt16.self) else {
                    return
                }
                let source = baseAddress.assumingMemoryBound(to: Float32.self)
                for row in 0..<height {
                    for column in 0..<width {
                        let valueMeters = max(source[(row * sourceBytesPerRow) + column], 0)
                        let valueMillimeters = min(valueMeters * 1000.0, Float(UInt16.max))
                        destination[(row * width) + column] = UInt16(valueMillimeters.rounded())
                    }
                }
            }
        default:
            throw WriterError.pixelBufferUnsupported
        }

        try writeGrayscalePNG(
            data: millimeterDepth,
            width: width,
            height: height,
            bitsPerComponent: 16,
            bytesPerRow: bytesPerRow,
            bitmapInfo: [
                .byteOrder16Little,
                CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            ],
            to: url
        )
    }

    private func writeConfidencePNG(from pixelBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw WriterError.pixelBufferBaseAddressUnavailable
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = width * MemoryLayout<UInt8>.size
        var confidenceData = Data(count: height * bytesPerRow)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_OneComponent8:
            confidenceData.withUnsafeMutableBytes { destinationBytes in
                guard let destination = destinationBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                let source = baseAddress.assumingMemoryBound(to: UInt8.self)
                for row in 0..<height {
                    for column in 0..<width {
                        destination[(row * width) + column] = source[(row * sourceBytesPerRow) + column]
                    }
                }
            }
        default:
            throw WriterError.pixelBufferUnsupported
        }

        try writeGrayscalePNG(
            data: confidenceData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            bitmapInfo: [CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)],
            to: url
        )
    }

    private func writeGrayscalePNG(
        data: Data,
        width: Int,
        height: Int,
        bitsPerComponent: Int,
        bytesPerRow: Int,
        bitmapInfo: [CGBitmapInfo],
        to url: URL
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let combinedBitmapInfo = bitmapInfo.reduce(CGBitmapInfo()) { partialResult, nextValue in
            partialResult.union(nextValue)
        }

        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: combinedBitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw WriterError.cgImageCreationFailed
        }

        try writeCGImage(image, to: url, typeIdentifier: UTType.png.identifier)
    }

    private func writeCGImage(
        _ cgImage: CGImage,
        to url: URL,
        typeIdentifier: String,
        properties: [CFString: Any] = [:]
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw WriterError.destinationCreationFailed
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw WriterError.imageEncodingFailed
        }
    }
}
