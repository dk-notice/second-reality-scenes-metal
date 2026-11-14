import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Saves a picture of a scene to a PNG file without opening a window:
///
///     SRMetal --snapshot <scene-id> <modern|classic> <step> <output.png>
///
/// Used to make the pictures in the documentation. The picture is 960x720 (4:3, like the app's window).
enum Snapshot {
    static let width = 960
    static let height = 720

    static func run(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.count >= flag + 5,
              let entry = SceneCatalog.all.first(where: { $0.id == arguments[flag + 1] }),
              let look = Look(rawValue: arguments[flag + 2]),
              let step = Int(arguments[flag + 3]) else {
            print("Usage: SRMetal --snapshot <scene-id> <modern|classic> <step> <output.png>")
            print("Scenes: " + SceneCatalog.all.map(\.id).joined(separator: ", "))
            return false
        }
        let output = URL(fileURLWithPath: arguments[flag + 4])

        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("No Metal graphics device available")
            return false
        }

        do {
            let scene = try entry.make(device, Renderer.pixelFormat)
            for _ in 0..<step { scene.tick() }

            // Pixels as blue, green, red, alpha, row by row.
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            guard let commands = queue.makeCommandBuffer() else { return false }

            switch look {
            case .modern:
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: false)
                descriptor.usage = [.renderTarget]
                descriptor.storageMode = .shared
                guard let texture = device.makeTexture(descriptor: descriptor),
                      let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: texture))
                else { return false }
                scene.draw(into: encoder, frame: FrameInfo(
                    look: .modern, alpha: 0, canvasSize: entry.canvasSize,
                    targetSize: SIMD2(Float(width), Float(height))))
                encoder.endEncoding()
                commands.commit()
                commands.waitUntilCompleted()
                texture.getBytes(&pixels, bytesPerRow: width * 4,
                                 from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

            case .classic:
                let smallWidth = Int(entry.canvasSize.x)
                let smallHeight = Int(entry.canvasSize.y)
                guard let texture = Renderer.makeClassicTexture(device: device, canvasSize: entry.canvasSize) else {
                    return false
                }
                Renderer.drawClassic(scene: scene, canvasSize: entry.canvasSize, into: texture, commands: commands)
                commands.commit()
                commands.waitUntilCompleted()
                var small = [UInt8](repeating: 0, count: smallWidth * smallHeight * 4)
                texture.getBytes(&small, bytesPerRow: smallWidth * 4,
                                 from: MTLRegionMake2D(0, 0, smallWidth, smallHeight), mipmapLevel: 0)
                // Scale up with hard-edged pixels, as the app does.
                for y in 0..<height {
                    let sourceY = y * smallHeight / height
                    for x in 0..<width {
                        let source = (sourceY * smallWidth + x * smallWidth / width) * 4
                        let target = (y * width + x) * 4
                        pixels[target] = small[source]
                        pixels[target + 1] = small[source + 1]
                        pixels[target + 2] = small[source + 2]
                        pixels[target + 3] = 255
                    }
                }
            }

            return writePNG(pixels: pixels, to: output)
        } catch {
            print("Could not start scene \(entry.title): \(error)")
            return false
        }
    }

    private static func writePNG(pixels: [UInt8], to url: URL) -> Bool {
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: colourSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            print("Could not create \(url.path)")
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            print("Could not write \(url.path)")
            return false
        }
        print("Wrote \(url.path)")
        return true
    }
}
