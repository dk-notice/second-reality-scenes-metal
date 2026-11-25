import AppKit
import CoreText
import MetalKit

/// `--scaler-compare <picture> <folder> [x y width]`: draws one of the demo's original pictures scaled
/// up four ways (`PictureScaler.Method`) and saves two labelled sheets of four, for choosing a scaler
/// by eye: `<picture>-full.png` (each whole picture at 960x720, a 4:3 screen) and `<picture>-zoom.png`
/// (one part of it, `width` source pixels wide starting at x, y, also at 960x720: what that part looks
/// like on a big screen). Without x y width the zoom shows the middle third.
enum ScalerCompareCommand {
    static let usage = "usage: SRMetal --scaler-compare <picture, e.g. 07-troll> <output folder> [x y width] [--methods a,b,...]"
    static let cell = (width: 960, height: 720)

    static func run(arguments: [String]) -> Bool {
        var arguments = arguments
        // Which ways to compare (default: the first four); names as in `PictureScaler.Method`.
        var methods = PictureScaler.Method.firstComparison
        if let at = arguments.firstIndex(of: "--methods"), at + 1 < arguments.count {
            let chosen = arguments[at + 1].split(separator: ",").compactMap { PictureScaler.Method(rawValue: String($0)) }
            guard !chosen.isEmpty else {
                print("--methods: use some of " + PictureScaler.Method.allCases.map(\.rawValue).joined(separator: ","))
                return false
            }
            methods = chosen
            arguments.removeSubrange(at...(at + 1))
        }
        guard let flag = arguments.firstIndex(of: "--scaler-compare"), arguments.count >= flag + 3 else {
            print(usage)
            return false
        }
        let name = arguments[flag + 1]
        let label = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let folder = URL(fileURLWithPath: arguments[flag + 2])
        // A picture by its artwork name, or any PNG file by its path.
        let file = name.hasSuffix(".png") ? URL(fileURLWithPath: name) : nil
        guard let url = file ?? DemoPictures.url(name) else {
            print("No picture called \(name) (names are those in artwork/original/rgb, without .png)")
            return false
        }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("No Metal graphics device")
            return false
        }
        do {
            let source = try MTKTextureLoader(device: device).newTexture(URL: url, options: [
                .SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue, .generateMipmaps: false])
            let scaler = try PictureScaler(device: device)
            let w = Float(source.width), h = Float(source.height)
            var zoom = SIMD4<Float>(1.0 / 3, 1.0 / 3, 1.0 / 3, 1.0 / 3)
            if arguments.count >= flag + 6, let x = Float(arguments[flag + 3]), let y = Float(arguments[flag + 4]),
               let width = Float(arguments[flag + 5]), width > 0 {
                // Same proportions as the whole picture, so the part also fills a 4:3 screen.
                zoom = SIMD4(x / w, y / h, width / w, width / w)
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (suffix, region) in [("full", SIMD4<Float>(0, 0, 1, 1)), ("zoom", zoom)] {
                let pictures = try methods.map { method -> CGImage in
                    try draw(source, method: method, region: region, scaler: scaler, device: device, queue: queue)
                }
                let title = suffix == "full" ? "\(label), whole picture"
                    : String(format: "%@, part from (%.0f, %.0f), %.0f source pixels wide", name,
                             region.x * w, region.y * h, region.z * w).replacingOccurrences(of: name, with: label)
                guard let sheet = sheet(pictures, labels: methods.map(\.title), title: title),
                      Snapshot.writePNG(sheet, to: folder.appendingPathComponent("\(label)-\(suffix).png")) else { return false }
            }
            return true
        } catch {
            print("\(name): \(error)")
            return false
        }
    }

    private static func draw(_ source: MTLTexture, method: PictureScaler.Method, region: SIMD4<Float>,
                             scaler: PictureScaler, device: MTLDevice, queue: MTLCommandQueue) throws -> CGImage {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: cell.width,
                                                                  height: cell.height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor), let commands = queue.makeCommandBuffer() else {
            throw Snapshot.Failure.couldNotDraw
        }
        scaler.draw(source, method: method, into: target, commands: commands, region: region)
        commands.commit()
        commands.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: cell.width * cell.height * 4)
        target.getBytes(&pixels, bytesPerRow: cell.width * 4, from: MTLRegionMake2D(0, 0, cell.width, cell.height), mipmapLevel: 0)
        guard let image = Snapshot.image(bgra: pixels, width: cell.width, height: cell.height) else { throw Snapshot.Failure.couldNotDraw }
        return image
    }

    /// The pictures two to a row, each with its label, and a title along the top.
    private static func sheet(_ pictures: [CGImage], labels: [String], title: String) -> CGImage? {
        let gap = 8, band = 36, top = 44
        let width = 2 * cell.width + 3 * gap
        let rows = (pictures.count + 1) / 2
        let height = top + rows * (cell.height + band) + gap
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func text(_ string: String, size: CGFloat, x: Int, yFromTop: Int) {
            let font = CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: CGColor(gray: 0.95, alpha: 1)]))
            context.textPosition = CGPoint(x: x, y: height - yFromTop)
            CTLineDraw(line, context)
        }
        text(title, size: 22, x: gap, yFromTop: 30)
        for (index, picture) in pictures.enumerated() {
            let column = index % 2, row = index / 2
            let x = gap + column * (cell.width + gap)
            let yTop = top + row * (cell.height + band)
            text("\(index + 1). \(labels[index])", size: 20, x: x, yFromTop: yTop + 26)
            context.draw(picture, in: CGRect(x: x, y: height - (yTop + band + cell.height), width: cell.width, height: cell.height))
        }
        return context.makeImage()
    }
}
