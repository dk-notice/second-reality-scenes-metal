import Foundation
import Metal

/// The command-line option that draws one of the VISU engine's test cases to a picture file,
/// without opening a window:
///
///     SRMetal --visu-test list
///     SRMetal --visu-test <case-name> <modern|classic> <output.png> [blend]
///
/// `classic` is the 1993 engine replay (320x200, shown at 960x720 with hard-edged pixels);
/// `modern` is the same objects as triangles on the graphics chip (960x720). For a whole-frame
/// case, `blend` (0...1) draws the modern picture that far between that frame and the next, the
/// way a scene glides between animation steps.
///
/// This is how to look at the engine by itself, apart from the scenes built on it.
enum VisuTestCommand {
    static let width = 960
    static let height = 720

    static func run(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--visu-test"), arguments.count > flag + 1 else {
            usage()
            return false
        }
        if arguments[flag + 1] == "compare" {
            // How close the modern picture is to the 1993 one, case by case (see the self-test).
            for test in VisuTestCases.all {
                if let d = try? difference(test.kind) { print(String(format: "%-26@ %.2f", test.name, d)) }
            }
            return true
        }
        if arguments[flag + 1] == "list" {
            for test in VisuTestCases.all { print(test.name) }
            return true
        }
        guard arguments.count >= flag + 4,
              let test = VisuTestCases.all.first(where: { $0.name == arguments[flag + 1] }),
              let look = Look(rawValue: arguments[flag + 2]) else {
            usage()
            return false
        }
        let output = URL(fileURLWithPath: arguments[flag + 3])
        let blend = arguments.count > flag + 4 ? Float(arguments[flag + 4]) ?? 0 : 0
        do {
            let pixels = try look == .classic ? classic(test.kind) : modern(test.kind, blend: blend)
            guard let image = Snapshot.image(bgra: pixels, width: width, height: height) else { return false }
            return Snapshot.writePNG(image, to: output)
        } catch {
            print("Could not draw \(test.name): \(error)")
            return false
        }
    }

    /// The average difference, per colour channel and pixel (0...255), between the 1993 picture
    /// and the modern one of the same test case. Small when the two show the same thing.
    static func difference(_ kind: VisuTestCases.Kind) throws -> Double {
        let a = try classic(kind), b = try modern(kind, blend: 0)
        var total = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
        }
        return Double(total) / Double(a.count / 4 * 3)
    }

    private static func usage() {
        print("Usage: SRMetal --visu-test list")
        print("       SRMetal --visu-test compare")
        print("       SRMetal --visu-test <case-name> <modern|classic> <output.png> [blend 0...1]")
    }

    /// For a run of frames, show its first frame.
    private static func single(_ kind: VisuTestCases.Kind) -> VisuTestCases.Kind {
        if case .run(let scene, let first, _, _) = kind { return .frame(scene: scene, frame: first) }
        return kind
    }

    /// The 1993 picture, scaled up to 960x720 with hard-edged pixels (blue, green, red, unused).
    static func classic(_ kind: VisuTestCases.Kind) throws -> [UInt8] {
        let prepared = try VisuTest.prepare(single(kind))
        let palette = VisuTest.palette(for: prepared.world)
        let indices = try VisuTest.classicPicture(single(kind)).pixels
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let sourceY = y * VisuEngine.height / height
            for x in 0..<width {
                let colour = Int(indices[sourceY * VisuEngine.width + x * VisuEngine.width / width]) * 3
                let target = (y * width + x) * 4
                pixels[target] = byteFromVGA(Int(palette[colour + 2]))
                pixels[target + 1] = byteFromVGA(Int(palette[colour + 1]))
                pixels[target + 2] = byteFromVGA(Int(palette[colour]))
            }
        }
        return pixels
    }

    /// The modern picture at 960x720 (blue, green, red, alpha).
    static func modern(_ kind: VisuTestCases.Kind, blend: Float) throws -> [UInt8] {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let commands = queue.makeCommandBuffer() else { throw Snapshot.Failure.noGraphicsDevice }
        let kind = single(kind)
        let prepared = try VisuTest.prepare(kind)
        var pose = VisuPose(items: prepared.objects.map { VisuPose.Item(object: $0, matrix: $0.inCamera.float4x4) })
        if blend > 0, case .frame = kind {
            // The next animation frame, and the pose part-way to it.
            prepared.world.advance()
            pose = pose.blended(to: prepared.world.pose(), alpha: blend)
        }

        // The view comes from the 1993 engine's own window and field-of-view routines.
        let engine = VisuEngine()
        VisuTest.setWindow(prepared.window, on: engine)
        engine.setCameraAngle(prepared.fieldOfView)

        let bytes = VisuTest.palette(for: prepared.world)
        var palette: [SIMD4<Float>] = []
        for i in 0..<256 {
            let red = Float(bytes[i * 3]) / 63
            let green = Float(bytes[i * 3 + 1]) / 63
            let blue = Float(bytes[i * 3 + 2]) / 63
            palette.append(SIMD4<Float>(red, green, blue, 1))
        }
        let renderer = try VisuModernRenderer(device: device, pixelFormat: Renderer.pixelFormat)
        renderer.render(pose, view: engine.view, palette: palette,
                        targetSize: SIMD2(Float(width), Float(height)), commands: commands)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: texture))
        else { throw Snapshot.Failure.couldNotDraw }
        renderer.composite(into: encoder)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }
}
