import Foundation
import simd

/// A scene's recorded animation being played: what the Ships Fly-by and the 3D City share.
///
/// It holds the scene's `VisuWorld`, the ONE `VisuEngine` that draws its 1993 pictures, and a second
/// copy of the animation kept one frame AHEAD, so that the modern look knows where everything is
/// going and can glide towards it. The scene decides when a frame is read (`step`) and what is
/// behind the objects; this class only keeps the two worlds and the two poses in order.
final class VisuPlayback {
    let world: VisuWorld
    /// The look-ahead copy. It is never drawn.
    private let ahead: VisuWorld
    let engine = VisuEngine()

    /// Where everything is in the animation frame now showing, and in the one after it.
    private(set) var currentPose = VisuPose(items: [])
    private(set) var nextPose = VisuPose(items: [])

    /// For each object of the look-ahead copy, its twin in `world`.
    private var twins: [ObjectIdentifier: VisuObject] = [:]
    /// The look-ahead pose last worked out, and which animation frame it is of.
    private var aheadPose = VisuPose(items: [])
    private var aheadPoseFrame = -1

    /// `name` is the scene's file name ("U2A" ships, "U2E" city); `distanceRule` is the scene
    /// program's own object-ordering rule, if it has one (see `VisuWorld.cityOrdering`).
    init(name: String, distanceRule: ((VisuObject, Int, Int) -> Int32?)? = nil) throws {
        world = try VisuWorld(name: name)
        ahead = try VisuWorld(name: name)
        world.distanceRule = distanceRule
        ahead.distanceRule = distanceRule
        for (mine, theirs) in zip(world.objects, ahead.objects) {
            if let mine, let theirs { twins[ObjectIdentifier(theirs)] = mine }
        }
        VisuWorld.setSceneWindow(engine)
    }

    /// Back to before the first animation frame. The engine remembers things from polygon to
    /// polygon (see docs/visu-engine.md, "Kept quirks"), so it goes back to its start too; without
    /// that a restart would not be exact.
    func restart() {
        world.restart()
        ahead.restart()
        engine.resetClipper()
        currentPose = VisuPose(items: [])
        nextPose = currentPose
        aheadPoseFrame = -1
    }

    /// One step of the scene. If `advancing`, the next animation frame is read. If `lookingAhead`,
    /// the frame after the one now showing is worked out for the modern look to glide towards;
    /// otherwise the modern look stays put for this step.
    func step(advancing: Bool, lookingAhead: Bool) {
        if advancing { world.advance() }
        currentPose = world.pose()
        guard lookingAhead else {
            nextPose = currentPose
            return
        }
        while ahead.frame <= world.frame && ahead.advance() {}
        if aheadPoseFrame != ahead.frame {
            // The look-ahead copy has its own objects; name each by its twin in `world`, because
            // the blend pairs up "now" and "next" by which object it is.
            aheadPose = VisuPose(items: ahead.pose().items.compactMap { item in
                guard let twin = twins[ObjectIdentifier(item.object)] else { return nil }
                return VisuPose.Item(object: twin, matrix: item.matrix)
            })
            aheadPoseFrame = ahead.frame
        }
        nextPose = aheadPose
    }

    /// The pose to draw `alpha` (0...1) of the way from the frame now showing to the next one.
    /// At 0 it is exactly what the 1993 look shows.
    func pose(alpha: Float) -> VisuPose {
        alpha <= 0 ? currentPose : currentPose.blended(to: nextPose, alpha: alpha)
    }

    /// A 320x200 picture of colour numbers as red, green, blue bytes (0...255) through a palette
    /// of 0...63 values: what the self-test compares the graphics chip's picture with.
    static func rgb(_ pixels: [UInt8], palette: [UInt8]) -> [UInt8] {
        var table = [UInt8](repeating: 0, count: 768)
        for i in 0..<768 { table[i] = byteFromVGA(Int(palette[i])) }
        var result = [UInt8](repeating: 0, count: pixels.count * 3)
        for (i, colour) in pixels.enumerated() {
            let c = Int(colour) * 3
            result[i * 3] = table[c]
            result[i * 3 + 1] = table[c + 1]
            result[i * 3 + 2] = table[c + 2]
        }
        return result
    }

    /// A palette of 0...63 values as the graphics chip wants it (0...1), times `brightness`.
    static func colours(_ palette: [UInt8], brightness: Float = 1) -> [SIMD4<Float>] {
        var result: [SIMD4<Float>] = []
        result.reserveCapacity(256)
        for i in 0..<256 {
            let red = Float(palette[i * 3]) / 63 * brightness
            let green = Float(palette[i * 3 + 1]) / 63 * brightness
            let blue = Float(palette[i * 3 + 2]) / 63 * brightness
            result.append(SIMD4<Float>(red, green, blue, 1))
        }
        return result
    }
}
