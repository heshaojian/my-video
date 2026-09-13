import CoreVideo
import ImageIO
import XCTest
@testable import MyVideo

final class PerceptualFrameHasherTests: XCTestCase {
    func testHashIsDeterministicAndStableAcrossUniformBrightnessChange() throws {
        let pixels = gradient(width: 48, height: 40, offset: 20)
        let brighter = pixels.map { UInt8(min(Int($0) + 24, 255)) }

        let first = try PerceptualFrameHasher.hash(
            luminanceBytes: pixels,
            width: 48,
            height: 40,
            bytesPerRow: 48
        )
        let second = try PerceptualFrameHasher.hash(
            luminanceBytes: pixels,
            width: 48,
            height: 40,
            bytesPerRow: 48
        )
        let shifted = try PerceptualFrameHasher.hash(
            luminanceBytes: brighter,
            width: 48,
            height: 40,
            bytesPerRow: 48
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, shifted)
    }

    func testDissimilarSpatialPatternsHaveLargeDistance() throws {
        let vertical = stripes(width: 64, height: 64, vertical: true)
        let horizontal = stripes(width: 64, height: 64, vertical: false)

        let verticalHash = try hash(vertical, width: 64, height: 64)
        let horizontalHash = try hash(horizontal, width: 64, height: 64)

        XCTAssertGreaterThan(
            PerceptualFrameHasher.hammingDistance(verticalHash, horizontalHash),
            10
        )
    }

    func testOddRowStridePaddingDoesNotAffectHash() throws {
        let width = 37
        let height = 35
        let compact = gradient(width: width, height: height, offset: 15)
        let bytesPerRow = 43
        var padded = [UInt8](repeating: 0xEE, count: bytesPerRow * height)
        for y in 0..<height {
            padded.replaceSubrange(
                (y * bytesPerRow)..<(y * bytesPerRow + width),
                with: compact[(y * width)..<(y * width + width)]
            )
        }

        XCTAssertEqual(
            try hash(compact, width: width, height: height),
            try PerceptualFrameHasher.hash(
                luminanceBytes: padded,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow
            )
        )
    }

    func testOrientationCorrectionProducesCanonicalHash() throws {
        let width = 40
        let height = 32
        let canonical = asymmetricPattern(width: width, height: height)
        let rotatedClockwise = rotateClockwise(canonical, width: width, height: height)

        let canonicalHash = try hash(canonical, width: width, height: height)
        let correctedHash = try PerceptualFrameHasher.hash(
            luminanceBytes: rotatedClockwise,
            width: height,
            height: width,
            bytesPerRow: height,
            orientation: .left
        )

        XCTAssertEqual(canonicalHash, correctedHash)
    }

    func testOneComponentPixelBufferMatchesByteBufferHash() throws {
        let width = 48
        let height = 40
        let pixels = asymmetricPattern(width: width, height: height)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                nil,
                width,
                height,
                kCVPixelFormatType_OneComponent8,
                nil,
                &buffer
            ),
            kCVReturnSuccess
        )
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        let rowStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            base.advanced(by: y * rowStride).copyMemory(
                from: pixels.withUnsafeBytes { $0.baseAddress!.advanced(by: y * width) },
                byteCount: width
            )
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        XCTAssertEqual(
            try PerceptualFrameHasher.hash(pixelBuffer: pixelBuffer),
            try hash(pixels, width: width, height: height)
        )
    }

    func testInvalidDimensionsAndUnboundedInputsAreRejected() {
        XCTAssertThrowsError(
            try PerceptualFrameHasher.hash(
                luminanceBytes: [1, 2, 3],
                width: 4,
                height: 4,
                bytesPerRow: 4
            )
        )
        XCTAssertThrowsError(
            try PerceptualFrameHasher.hash(
                luminanceBytes: [UInt8](repeating: 0, count: 1),
                width: 20_000,
                height: 20_000,
                bytesPerRow: 20_000
            )
        )
    }

    func testHammingDistanceCountsDifferingBitsExactly() {
        XCTAssertEqual(PerceptualFrameHasher.hammingDistance(0, 0), 0)
        XCTAssertEqual(PerceptualFrameHasher.hammingDistance(0, UInt64.max), 64)
        XCTAssertEqual(PerceptualFrameHasher.hammingDistance(0b1010, 0b0011), 2)
    }

    private func hash(_ pixels: [UInt8], width: Int, height: Int) throws -> UInt64 {
        try PerceptualFrameHasher.hash(
            luminanceBytes: pixels,
            width: width,
            height: height,
            bytesPerRow: width
        )
    }

    private func gradient(width: Int, height: Int, offset: Int) -> [UInt8] {
        (0..<(width * height)).map { index in
            let x = index % width
            let y = index / width
            return UInt8(offset + ((x * 3 + y * 2) % 150))
        }
    }

    private func stripes(width: Int, height: Int, vertical: Bool) -> [UInt8] {
        (0..<(width * height)).map { index in
            let x = index % width
            let y = index / width
            let coordinate = vertical ? x : y
            return (coordinate / 8).isMultiple(of: 2) ? 20 : 230
        }
    }

    private func asymmetricPattern(width: Int, height: Int) -> [UInt8] {
        (0..<(width * height)).map { index in
            let x = index % width
            let y = index / width
            if x < width / 3, y < height / 2 { return 230 }
            if x > width / 2, y > height * 2 / 3 { return 150 }
            return UInt8((x * 5 + y * 3) % 90)
        }
    }

    private func rotateClockwise(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        let rotatedWidth = height
        var output = [UInt8](repeating: 0, count: pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                let rotatedX = height - 1 - y
                let rotatedY = x
                output[rotatedY * rotatedWidth + rotatedX] = pixels[y * width + x]
            }
        }
        return output
    }
}
