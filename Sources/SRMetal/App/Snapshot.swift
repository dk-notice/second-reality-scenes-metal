import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Draws a picture of a scene without a window. Two users:
///
/// - the command-line option that makes the pictures in the documentation:
///
///       SRMetal --snapshot <scene-id> <modern|classic> <step> <output.png> [blend]
///
///   (960x720: 4:3, like the scene picture in the app's window). The optional `blend` (0...1,
///   modern look only) draws the picture that far from that step towards the next, as the app
///   does between steps; it is for checking that motion is smooth. And
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
        guard let request = request(from: arguments) else {
            print("Usage: SRMetal --snapshot <scene-id> <modern|classic> <step> <output.png> [blend 0...1]")
            print("(step: a whole number, 0 or more)")
            print("Scenes: " + SceneCatalog.all.map(\.id).joined(separator: ", ") + ", " + DemoRunScene.id)
            return false
        }
        do {
            let image = try render(entry: request.entry, look: request.look, step: request.step,
                                   width: width, height: height, alpha: request.blend)
            return writePNG(image, to: URL(fileURLWithPath: request.output))
        } catch {
            print("Could not draw scene \(request.entry.title): \(error)")
            return false
        }
    }

    /// What a `--snapshot` command line asks for.
    struct Request {
        var entry: SceneEntry
        var look: Look
        var step: Int
        var output: String
        var blend: Float
    }

    /// Reads the command line; nil if it does not make sense (unknown scene or look, a step that
    /// is not a whole number of 0 or more, a blend that is not a number). A blend outside 0...1 is
    /// brought to the nearer end.
    static func request(from arguments: [String]) -> Request? {
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.count >= flag + 5,
              let entry = SceneCatalog.all.first(where: { $0.id == arguments[flag + 1] })
                  ?? (arguments[flag + 1] == DemoRunScene.id ? DemoTimelineCommand.silentEntry : nil),
              let look = Look(rawValue: arguments[flag + 2]),
              let step = Int(arguments[flag + 3]), step >= 0 else { return nil }
        var blend: Float = 0
        if arguments.count > flag + 5 {
            guard let given = Float(arguments[flag + 5]), given.isFinite else { return nil }
            blend = min(max(given, 0), 1)
        }
        return Request(entry: entry, look: look, step: step, output: arguments[flag + 4], blend: blend)
    }

    /// Starts a fresh copy of a scene, runs it for `step` steps and returns a picture of what it then
    /// shows, `width` x `height` pixels. Opens no window, and is safe to call away from the main thread:
    /// it makes its own scene and talks to the graphics chip through its own queue. `alpha` is how
    /// far past the step to draw the modern look (0 = exactly on the step).
    static func render(entry: SceneEntry, look: Look, step: Int, width: Int, height: Int, alpha: Float = 0) throws -> CGImage {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Failure.noGraphicsDevice
        }

        let scene = try entry.make(device, Renderer.pixelFormat)
        for _ in 0..<step { scene.tick() }
        // Play Demo's canvas changes with the part it is showing.
        let canvasSize = scene.currentCanvasSize ?? entry.canvasSize

        // Pixels as blue, green, red, alpha, row by row.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let commands = queue.makeCommandBuffer() else { throw Failure.couldNotDraw }

        switch look {
        case .modern:
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget]
            descriptor.storageMode = .shared
            let frame = FrameInfo(look: .modern, alpha: alpha, canvasSize: canvasSize,
                                  targetSize: SIMD2(Float(width), Float(height)))
            scene.prepare(commands: commands, frame: frame)
            guard let texture = device.makeTexture(descriptor: descriptor),
                  let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: texture))
            else { throw Failure.couldNotDraw }
            scene.draw(into: encoder, frame: frame)
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            texture.getBytes(&pixels, bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        case .classic:
            let smallWidth = Int(canvasSize.x)
            let smallHeight = Int(canvasSize.y)
            guard let texture = Renderer.makeClassicTexture(device: device, canvasSize: canvasSize) else {
                throw Failure.couldNotDraw
            }
            Renderer.drawClassic(scene: scene, canvasSize: canvasSize, into: texture, commands: commands)
            commands.commit()
            commands.waitUntilCompleted()
            var small = [UInt8](repeating: 0, count: smallWidth * smallHeight * 4)
            texture.getBytes(&small, bytesPerRow: smallWidth * 4,
                             from: MTLRegionMake2D(0, 0, smallWidth, smallHeight), mipmapLevel: 0)
            // Scale up with hard-edged pixels, as the app does: each picture pixel takes the canvas
            // pixel under its CENTRE (hence the "2 * ... + 1": the centre of pixel y is at y + 1/2).
            for y in 0..<height {
                let sourceY = (2 * y + 1) * smallHeight / (2 * height)
                for x in 0..<width {
                    let source = (sourceY * smallWidth + (2 * x + 1) * smallWidth / (2 * width)) * 4
                    let target = (y * width + x) * 4
                    pixels[target] = small[source]
                    pixels[target + 1] = small[source + 1]
                    pixels[target + 2] = small[source + 2]
                    pixels[target + 3] = 255
                }
            }
        }

        guard let image = image(bgra: pixels, width: width, height: height) else { throw Failure.couldNotDraw }
        return image
    }

    /// A picture from pixels given as blue, green, red, (unused) bytes, row by row.
    static func image(bgra pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: colourSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return image
    }

    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
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
