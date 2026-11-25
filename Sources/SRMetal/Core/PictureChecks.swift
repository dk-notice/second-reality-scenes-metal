import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for the Modern look's picture scaler and the shared picture fades (run by `CoreChecks.run`; see `App/CoreChecks.swift`).
extension CoreChecks {
    // MARK: - The Modern look's picture scaler (Super-xBR; added 2026-11-24)

    static func pictureScaler(_ check: (String, Bool, String) -> Void, device: MTLDevice, queue: MTLCommandQueue) throws {
        /// An 8-bit picture on the graphics chip, from red, green, blue bytes.
        func picture(_ rgb: [UInt8], width: Int, height: Int) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            var rgba = [UInt8]()
            for i in 0..<(width * height) { rgba += [rgb[3 * i], rgb[3 * i + 1], rgb[3 * i + 2], 255] }
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: rgba, bytesPerRow: width * 4)
            return texture
        }
        /// The upscaled picture's red, green, blue values (0...1), read back from the graphics chip.
        func readBack(_ texture: MTLTexture) -> [Float] {
            let w = texture.width, h = texture.height
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false)
            descriptor.storageMode = .shared
            guard let copy = device.makeTexture(descriptor: descriptor), let commands = queue.makeCommandBuffer(),
                  let blit = commands.makeBlitCommandEncoder() else { return [] }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, to: copy, destinationSlice: 0, destinationLevel: 0,
                      sliceCount: 1, levelCount: 1)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            var halves = [UInt16](repeating: 0, count: w * h * 4)
            copy.getBytes(&halves, bytesPerRow: w * 8, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            var out = [Float]()
            out.reserveCapacity(w * h * 3)
            for i in 0..<(w * h) { for k in 0..<3 { out.append(floatFromHalf(halves[4 * i + k])) } }
            return out
        }

        // A flat colour stays exactly that colour.
        let flatRGB = [UInt8](repeating: 0, count: 16 * 16 * 3).enumerated().map { [UInt8(200), 90, 30][$0.offset % 3] }
        let flatName = "Picture scaler: Super-xBR makes a picture exactly \(PictureScaler.modernScale) times larger, and leaves a flat colour unchanged"
        if let flat = picture(flatRGB, width: 16, height: 16) {
            let big = try PictureScaler.upscaled(flat, device: device)
            let values = readBack(big)
            let worst = zip(values, (0..<values.count).map { Float([200, 90, 30][$0 % 3]) / 255 }).map { abs($0 - $1) }.max() ?? 1
            check(flatName, big.width == 16 * PictureScaler.modernScale && big.height == 16 * PictureScaler.modernScale && worst < 0.002, "largest change \(worst)")
        } else {
            check(flatName, false, "the test picture could not be made")
        }

        // On a real picture (the troll: dithering, gradients, hard edges) every new pixel stays within
        // the colours of the original pixels around it: no invented colours, no halos.
        guard let rgb = ScenePicture.pixels("07-troll") else {
            check("Picture scaler: the troll picture is there to test with", false, "")
            return
        }
        let troll = try ScenePicture(named: "07-troll", device: device).original
        let w = troll.width, h = troll.height
        func original(_ x: Int, _ y: Int, _ k: Int) -> Float {
            Float(rgb[(min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)) * 3 + k]) / 255
        }
        let big = try PictureScaler.upscaled(troll, device: device)
        let values = readBack(big)
        let scale = PictureScaler.modernScale
        let trollName = "Picture scaler: Super-xBR on the troll keeps every new pixel within the colours of the original pixels around it"
        guard values.count == scale * w * scale * h * 3 else {
            check(trollName, false, "the scaled picture could not be read back (\(values.count) values)")
            return
        }
        // The lowest and highest value of each colour among the original pixels within 2 of each pixel.
        var lowest = [Float](repeating: 1, count: w * h * 3), highest = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                for k in 0..<3 {
                    for sy in (y - 2)...(y + 2) {
                        for sx in (x - 2)...(x + 2) {
                            let v = original(sx, sy, k)
                            lowest[(y * w + x) * 3 + k] = min(lowest[(y * w + x) * 3 + k], v)
                            highest[(y * w + x) * 3 + k] = max(highest[(y * w + x) * 3 + k], v)
                        }
                    }
                }
            }
        }
        var outside = 0, worst: Float = 0
        for y in 0..<(scale * h) {
            for x in 0..<(scale * w) {
                let near = ((y / scale) * w + x / scale) * 3
                for k in 0..<3 {
                    let v = values[(y * scale * w + x) * 3 + k]
                    let off = max(lowest[near + k] - v, v - highest[near + k])
                    if off > 0.002 { outside += 1; worst = max(worst, off) }
                }
            }
        }
        check(trollName, big.width == scale * w && big.height == scale * h && outside == 0, "\(outside) values outside, worst by \(worst)")
    }

    /// The shared picture-and-fade toolkit (added 2026-11-24): in the 1993 look a fade gives exactly the
    /// colour levels the original's whole-number rule gives, towards white and towards black.
    static func pictureFades(_ check: (String, Bool, String) -> Void, device: MTLDevice, queue: MTLCommandQueue) throws {
        let levels = [0, 1, 2, 17, 31, 32, 33, 50, 62, 63]   // 1993 colour levels, one per pixel
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: levels.count, height: 1, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw Snapshot.Failure.couldNotDraw }
        // Red = the level, green = 63 - level, blue = a third of it: three different values per pixel.
        let rgba: [UInt8] = levels.flatMap { level -> [UInt8] in
            [byteFromVGA(level), byteFromVGA(63 - level), byteFromVGA(level / 3), 255]
        }
        texture.replace(region: MTLRegionMake2D(0, 0, levels.count, 1), mipmapLevel: 0, withBytes: rgba, bytesPerRow: levels.count * 4)
        let picture = ScenePicture(texture, device: device)
        let layer = try PictureLayer.shared(device: device, pixelFormat: Renderer.pixelFormat)
        var wrong = 0, tried = 0
        for fade in [PictureFade.none, .white(1), .white(32), .white(63), .fromWhite(keep: 0, outOf: 128),
                     .fromWhite(keep: 37, outOf: 128), .fromWhite(keep: 127, outOf: 128), .toBlack(keep: 63, outOf: 64),
                     .toBlack(keep: 20, outOf: 64), .toBlack(keep: 0, outOf: 64)] {
            let drawn = try draw(width: levels.count, height: 1, device: device, queue: queue) { encoder in
                layer.draw(picture, into: encoder, look: .classic, fade: fade)
            }
            for (x, level) in levels.enumerated() {
                let expected = [level, 63 - level, level / 3].map { byteFromVGA(fade.classicLevel($0)) }
                let got = [drawn[x * 4 + 2], drawn[x * 4 + 1], drawn[x * 4]]   // stored blue, green, red
                tried += 1
                if got != expected { wrong += 1 }
            }
        }
        check("Pictures: 1993-look fades (64ths and 128ths, to white and to black) give exactly the original rules' colours",
              wrong == 0, "\(wrong) of \(tried) pixels differ")
    }

    /// A 16-bit floating-point number (as the graphics chip stores it) as an ordinary one.
    private static func floatFromHalf(_ bits: UInt16) -> Float {
        let sign: Float = bits & 0x8000 != 0 ? -1 : 1
        let exponent = Int((bits >> 10) & 0x1F), fraction = Float(bits & 0x3FF)
        if exponent == 0 { return sign * fraction / 1024 * pow(2, -14) }
        if exponent == 31 { return fraction == 0 ? sign * .infinity : .nan }
        return sign * (1 + fraction / 1024) * pow(2, Float(exponent - 15))
    }
}
