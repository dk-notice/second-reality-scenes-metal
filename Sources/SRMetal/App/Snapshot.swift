import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Draws a picture of a scene without a window. Two users:
///
/// - the command-line option that makes the pictures in the documentation:
///
///       SRMetal --snapshot <scene-id> <modern|classic> <step> <output.png>
///
///   (960x720: 4:3, like the scene picture in the app's window), and
/// - the small pictures in the window's scene list (see `Thumbnails.swift`).
enum Snapshot {
    static let width = 960
    static let height = 720

    enum Failure: Error, CustomStringConvertible {
        case noGraphicsDevice
        case couldNotDraw

        var description: String {
            switch self {
            case .noGraphicsDevice: return "No Metal graphics device available"
            case .couldNotDraw: return "The graphics device could not draw the picture"
            }
        }
    }

    /// The command-line option: works out what was asked for, renders it and writes the PNG file.
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

        do {
            let image = try render(entry: entry, look: look, step: step, width: width, height: height)
            return writePNG(image, to: output)
        } catch {
            print("Could not draw scene \(entry.title): \(error)")
            return false
        }
    }

    /// Starts a fresh copy of a scene, runs it for `step` steps and returns a picture of what it then
    /// shows, `width` x `height` pixels. Opens no window, and is safe to call away from the main thread:
    /// it makes its own scene and talks to the graphics chip through its own queue.
    static func render(entry: SceneEntry, look: Look, step: Int, width: Int, height: Int) throws -> CGImage {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Failure.noGraphicsDevice
        }

        let scene = try entry.make(device, Renderer.pixelFormat)
        for _ in 0..<step { scene.tick() }

        // Pixels as blue, green, red, alpha, row by row.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let commands = queue.makeCommandBuffer() else { throw Failure.couldNotDraw }

        switch look {
        case .modern:
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor),
                  let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: texture))
            else { throw Failure.couldNotDraw }
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
                throw Failure.couldNotDraw
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

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: colourSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw Failure.couldNotDraw }
        return image
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
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
