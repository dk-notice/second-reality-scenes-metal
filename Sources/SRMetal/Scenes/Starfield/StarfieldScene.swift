import Metal
import simd

/// Draws the hidden starfield.
///
///  - Classic look: the processor replays the 1993 steps (64 off-screen pictures that are never wiped)
///    and the graphics chip turns the colour numbers into colours, on a 320x400 canvas.
///  - Modern look: the graphics chip draws every star as a soft round point at full resolution. The
///    model remembers each star's flight, so the shader can place it anywhere between two steps.
final class StarfieldScene: DemoScene {
    private(set) var model = StarfieldModel()
    private let indexedCanvas: IndexedCanvas
    private let pipeline: MTLRenderPipelineState
    private let device: MTLDevice
    /// A few buffers used in turn, so a new frame's list never overwrites one still being drawn.
    private var flightBuffers: [MTLBuffer?] = [nil, nil, nil]
    private var nextBuffer = 0

    /// Must match `Uniforms` in the shader source below.
    private struct Uniforms {
        var canvasSize: SIMD2<Float>
        var targetSize: SIMD2<Float>
        var time: Float         // steps since the start, with the fraction towards the next step
        var brightness: Float   // the fade, 0...1
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        indexedCanvas = try IndexedCanvas(
            device: device, pixelFormat: pixelFormat,
            width: StarfieldModel.width, height: StarfieldModel.height)

        let library = try Shaders.library(device: device, source: Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("starfield_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("starfield_fragment", in: library)
        let colour = descriptor.colorAttachments[0]!
        colour.pixelFormat = pixelFormat
        // Light adds up: where stars overlap, the result is brighter. (The original combined colour
        // numbers on overlap, which also made overlaps brighter.)
        colour.isBlendingEnabled = true
        colour.sourceRGBBlendFactor = .one
        colour.sourceAlphaBlendFactor = .one
        colour.destinationRGBBlendFactor = .one
        colour.destinationAlphaBlendFactor = .one
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }

    func classicReferenceFrame() -> [UInt8] {
        let palette = model.classicPalette()
        var frame = [UInt8]()
        frame.reserveCapacity(StarfieldModel.width * StarfieldModel.height * 3)
        for index in model.classicIndices() {
            let colour = palette[Int(index)]
            frame.append(byteFromVGA(colour.x))
            frame.append(byteFromVGA(colour.y))
            frame.append(byteFromVGA(colour.z))
        }
        return frame
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            indexedCanvas.draw(
                into: encoder,
                indices: model.classicIndices(),
                palette: model.classicPalette().map { SIMD4<Float>(SIMD3<Float>($0) / 63, 1) })
            return
        }

        let flights = model.flights
        guard !flights.isEmpty, model.ticks > 0 else { return }

        // Copy the list of flights to the graphics chip. Make the buffer bigger when the list outgrows it.
        let needed = MemoryLayout<StarfieldModel.Flight>.stride * flights.count
        if (flightBuffers[nextBuffer]?.length ?? 0) < needed {
            flightBuffers[nextBuffer] = device.makeBuffer(length: max(needed * 2, 1 << 16), options: .storageModeShared)
        }
        guard let buffer = flightBuffers[nextBuffer] else { return }
        nextBuffer = (nextBuffer + 1) % flightBuffers.count
        flights.withUnsafeBytes { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }

        // The fade glides between this step's level and the next one's.
        func brightness(_ tick: Int) -> Float {
            Float(min(StarfieldModel.fadeLevel(tick: tick) * 8, 255)) / 255
        }
        var uniforms = Uniforms(
            canvasSize: frame.canvasSize,
            targetSize: frame.targetSize,
            time: Float(model.ticks) + frame.alpha,
            brightness: simd_mix(brightness(model.ticks), brightness(model.ticks + 1), frame.alpha))

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        // Each flight can be on screen up to four times at once: twice in the top half (the film loop is
        // 64 steps long and a flight lasts up to 127) and twice in the mirrored bottom half.
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: flights.count * 4)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Flight {
        float x;            // the star's place, -512...511
        float y;
        float start;        // first step it was drawn on
        float startDepth;   // its depth on that step (255 far ... 0 near)
        float end;          // the step it stopped on (not included)
        float unused0, unused1, unused2;
    };

    struct Uniforms {
        float2 canvasSize;  // 320 x 400
        float2 targetSize;
        float time;
        float brightness;
    };

    struct StarOut {
        float4 position [[position]];
        float2 uv;          // -1...1 across the star's square
        float3 colour;
        float edge;         // soft-edge width as a fraction of the radius
    };

    // Runs once per corner of every star, and works out where that corner goes on screen.
    vertex StarOut starfield_vertex(uint vid [[vertex_id]],
                                    uint iid [[instance_id]],
                                    const device Flight *flights [[buffer(0)]],
                                    constant Uniforms &u [[buffer(1)]]) {
        Flight f = flights[iid / 4];
        bool mirrored = (iid & 1) != 0;
        float lap = float((iid >> 1) & 1);

        // The top half shows picture number (time mod 64); the bottom half the one 32 steps behind.
        // A picture holds this flight's dot from every 64th step, so find the latest such step that the
        // flight had reached, and (for lap 1) the one before it.
        float t = u.time - (mirrored ? 32.0 : 0.0);
        float laps = (t >= f.end) ? floor((t - f.end) / 64.0) + 1.0 : 0.0;
        float step = t - 64.0 * (laps + lap);

        StarOut out;
        out.uv = float2(0.0);
        out.colour = float3(0.0);
        out.edge = 1.0;
        if (step < f.start || step >= f.end) {
            out.position = float4(0.0, 0.0, -2.0, 1.0);   // nothing to draw: put it outside the view
            return out;
        }

        // The original's perspective, without the whole-number rounding.
        float depth = f.startDepth - 2.0 * (step - f.start);
        float distance = 150.0 + 4.0 * depth;
        float sx = f.x * 288.0 / distance;
        float sy = f.y * 216.0 / distance;              // negative: above the horizon
        float2 centre = float2(160.5 + sx, mirrored ? 199.5 - 2.0 * sy : 199.5 + 2.0 * sy);

        // Nearer stars are bigger and brighter. The original's were all one pixel, in three shades.
        float nearness = saturate(1.0 - depth / 255.0);
        float2 pixelsPerUnit = u.targetSize / u.canvasSize;
        float diameter = max((0.9 + 2.6 * nearness * nearness) * pixelsPerUnit.y, 2.2);   // real pixels

        const float3 dim = float3(16.0, 20.0, 25.0) / 63.0;
        const float3 middle = float3(24.0, 31.0, 37.0) / 63.0;
        const float3 bright = float3(41.0, 52.0, 62.0) / 63.0;
        float3 colour = depth > 145.0
            ? mix(middle, dim, saturate((depth - 145.0) / 72.0))
            : mix(bright, middle, saturate((depth - 55.0) / 90.0));
        // Ease in when a star appears and out when it stops, instead of popping.
        float ease = saturate((step - f.start + 1.0) / 6.0) * saturate((f.end - step) / 4.0);

        float2 corner = float2(vid & 1, vid >> 1) * 2.0 - 1.0;
        float2 pos = centre + corner * 0.5 * diameter / pixelsPerUnit;
        float2 ndc = pos / u.canvasSize * 2.0 - 1.0;
        out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
        out.uv = corner;
        out.colour = colour * ease * u.brightness;
        out.edge = max(2.0 / diameter, 0.45);
        return out;
    }

    // Runs once per pixel of every star: a round point with a soft rim.
    fragment float4 starfield_fragment(StarOut in [[stage_in]]) {
        float alpha = saturate((1.0 - length(in.uv)) / in.edge);
        return float4(in.colour * alpha, alpha);
    }
    """
}
