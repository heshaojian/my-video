import CoreVideo
import Foundation
import ImageIO

enum PerceptualFrameHasher {
    enum HashError: Error, Equatable {
        case invalidDimensions
        case invalidBuffer
        case unsupportedPixelFormat
    }

    private static let downscaledSide = 32
    private static let hashSide = 8
    private static let maximumDimension = 8_192
    private static let maximumPixels = 36_000_000

    static func hash(
        luminanceBytes: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> UInt64 {
        try validateDimensions(width: width, height: height, bytesPerRow: bytesPerRow)
        guard luminanceBytes.count >= (try requiredByteCount(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow
        )) else {
            throw HashError.invalidBuffer
        }

        return try luminanceBytes.withUnsafeBytes { rawBytes in
            guard let base = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw HashError.invalidBuffer
            }
            return makeHash(width: width, height: height, orientation: orientation) { x, y in
                base[y * bytesPerRow + x]
            }
        }
    }

    static func hash(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> UInt64 {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        if CVPixelBufferIsPlanar(pixelBuffer), CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            try validateDimensions(width: width, height: height, bytesPerRow: bytesPerRow)
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?
                .assumingMemoryBound(to: UInt8.self) else {
                throw HashError.invalidBuffer
            }
            return makeHash(width: width, height: height, orientation: orientation) { x, y in
                base[y * bytesPerRow + x]
            }
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer)?
            .assumingMemoryBound(to: UInt8.self) else {
            throw HashError.invalidBuffer
        }

        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_OneComponent8:
            try validateDimensions(width: width, height: height, bytesPerRow: bytesPerRow)
            return makeHash(width: width, height: height, orientation: orientation) { x, y in
                base[y * bytesPerRow + x]
            }
        case kCVPixelFormatType_32BGRA:
            try validatePackedDimensions(width: width, height: height, bytesPerRow: bytesPerRow)
            return makeHash(width: width, height: height, orientation: orientation) { x, y in
                let pixel = base.advanced(by: y * bytesPerRow + x * 4)
                return luminance(red: pixel[2], green: pixel[1], blue: pixel[0])
            }
        case kCVPixelFormatType_32ARGB:
            try validatePackedDimensions(width: width, height: height, bytesPerRow: bytesPerRow)
            return makeHash(width: width, height: height, orientation: orientation) { x, y in
                let pixel = base.advanced(by: y * bytesPerRow + x * 4)
                return luminance(red: pixel[1], green: pixel[2], blue: pixel[3])
            }
        case kCVPixelFormatType_32RGBA:
            try validatePackedDimensions(width: width, height: height, bytesPerRow: bytesPerRow)
            return makeHash(width: width, height: height, orientation: orientation) { x, y in
                let pixel = base.advanced(by: y * bytesPerRow + x * 4)
                return luminance(red: pixel[0], green: pixel[1], blue: pixel[2])
            }
        default:
            throw HashError.unsupportedPixelFormat
        }
    }

    static func hammingDistance(_ first: UInt64, _ second: UInt64) -> Int {
        (first ^ second).nonzeroBitCount
    }

    private static func makeHash(
        width: Int,
        height: Int,
        orientation: CGImagePropertyOrientation,
        luminanceAt: (Int, Int) -> UInt8
    ) -> UInt64 {
        let size = orientedDimensions(width: width, height: height, orientation: orientation)
        var downscaled = [UInt16](repeating: 0, count: downscaledSide * downscaledSide)

        for outputY in 0..<downscaledSide {
            let yRange = sourceRange(index: outputY, sourceLength: size.height)
            for outputX in 0..<downscaledSide {
                let xRange = sourceRange(index: outputX, sourceLength: size.width)
                var sum: UInt64 = 0
                var count: UInt64 = 0
                for orientedY in yRange {
                    for orientedX in xRange {
                        let source = sourceCoordinate(
                            x: orientedX,
                            y: orientedY,
                            width: width,
                            height: height,
                            orientation: orientation
                        )
                        sum += UInt64(luminanceAt(source.x, source.y))
                        count += 1
                    }
                }
                downscaled[outputY * downscaledSide + outputX] = UInt16(sum / max(count, 1))
            }
        }

        let blockSide = downscaledSide / hashSide
        var blocks = [UInt32](repeating: 0, count: hashSide * hashSide)
        for blockY in 0..<hashSide {
            for blockX in 0..<hashSide {
                var sum: UInt32 = 0
                for y in (blockY * blockSide)..<((blockY + 1) * blockSide) {
                    for x in (blockX * blockSide)..<((blockX + 1) * blockSide) {
                        sum += UInt32(downscaled[y * downscaledSide + x])
                    }
                }
                blocks[blockY * hashSide + blockX] = sum
            }
        }

        let mean = blocks.reduce(UInt64(0)) { $0 + UInt64($1) } / UInt64(blocks.count)
        return blocks.enumerated().reduce(UInt64(0)) { hash, entry in
            UInt64(entry.element) > mean
                ? hash | (UInt64(1) << UInt64(entry.offset))
                : hash
        }
    }

    private static func validateDimensions(width: Int, height: Int, bytesPerRow: Int) throws {
        guard
            width > 0,
            height > 0,
            width <= maximumDimension,
            height <= maximumDimension,
            bytesPerRow >= width,
            width <= maximumPixels / height
        else {
            throw HashError.invalidDimensions
        }
    }

    private static func validatePackedDimensions(
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) throws {
        try validateDimensions(width: width, height: height, bytesPerRow: bytesPerRow / 4)
        guard width <= Int.max / 4, bytesPerRow >= width * 4 else {
            throw HashError.invalidDimensions
        }
    }

    private static func requiredByteCount(
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) throws -> Int {
        let (rowOffset, rowOverflow) = (height - 1).multipliedReportingOverflow(by: bytesPerRow)
        let (required, additionOverflow) = rowOffset.addingReportingOverflow(width)
        guard !rowOverflow, !additionOverflow else {
            throw HashError.invalidDimensions
        }
        return required
    }

    private static func orientedDimensions(
        width: Int,
        height: Int,
        orientation: CGImagePropertyOrientation
    ) -> (width: Int, height: Int) {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: (height, width)
        default: (width, height)
        }
    }

    private static func sourceRange(index: Int, sourceLength: Int) -> Range<Int> {
        let lower = index * sourceLength / downscaledSide
        let upper = max(lower + 1, (index + 1) * sourceLength / downscaledSide)
        return lower..<min(upper, sourceLength)
    }

    private static func sourceCoordinate(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        orientation: CGImagePropertyOrientation
    ) -> (x: Int, y: Int) {
        switch orientation {
        case .up: (x, y)
        case .upMirrored: (width - 1 - x, y)
        case .down: (width - 1 - x, height - 1 - y)
        case .downMirrored: (x, height - 1 - y)
        case .leftMirrored: (y, x)
        case .right: (y, height - 1 - x)
        case .rightMirrored: (width - 1 - y, height - 1 - x)
        case .left: (width - 1 - y, x)
        @unknown default: (x, y)
        }
    }

    private static func luminance(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
        UInt8((UInt16(red) * 54 + UInt16(green) * 183 + UInt16(blue) * 19) >> 8)
    }
}

struct DefaultSkipFrameHasher: SkipFrameHashing {
    func hash(_ frame: SkipVideoFrame) async throws -> UInt64 {
        try PerceptualFrameHasher.hash(pixelBuffer: frame.pixelBuffer)
    }
}
