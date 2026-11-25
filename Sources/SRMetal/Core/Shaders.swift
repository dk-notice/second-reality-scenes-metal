import Metal

enum ShaderError: Error, CustomStringConvertible {
    case missingFunction(String)

    var description: String {
        switch self {
        case .missingFunction(let name): return "Shader function not found: \(name)"
        }
    }
}

enum Shaders {
    /// Compiles shader source when the app starts. (Shaders are small programs that run on the graphics chip.)
    /// Compiling at start-up means the project builds with Apple's command-line tools alone; no Xcode needed.
    static func library(device: MTLDevice, source: String) throws -> MTLLibrary {
        let options = MTLCompileOptions()
        // Exact maths, so the classic look rounds the same way the original did.
        options.mathMode = .safe
        return try device.makeLibrary(source: source, options: options)
    }

    /// A sampler for pictures, edges clamped: `smooth` = linear with mipmaps (Modern look), otherwise
    /// nearest pixel (1993 look). `anisotropy` above 1 lets a picture squashed one way stay sharp the other.
    static func sampler(device: MTLDevice, smooth: Bool, anisotropy: Int = 1) throws -> MTLSamplerState {
        let d = MTLSamplerDescriptor()
        d.minFilter = smooth ? .linear : .nearest
        d.magFilter = smooth ? .linear : .nearest
        d.mipFilter = smooth ? .linear : .notMipmapped
        d.maxAnisotropy = anisotropy
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        guard let state = device.makeSamplerState(descriptor: d) else { throw RendererError.noSampler }
        return state
    }

    static func function(_ name: String, in library: MTLLibrary) throws -> MTLFunction {
        guard let function = library.makeFunction(name: name) else {
            throw ShaderError.missingFunction(name)
        }
        return function
    }

    /// Shared start of any shader that paints the whole canvas (as opposed to drawing separate shapes).
    /// It covers the viewport with one oversized triangle; `uv` runs from (0,0) at the top-left
    /// to (1,1) at the bottom-right. Draw it with 3 vertices.
    static let canvasVertexSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CanvasOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex CanvasOut canvas_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        CanvasOut out;
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        out.uv = float2(p.x, 1.0 - p.y);
        return out;
    }

    """

    /// Copies the small classic-look picture onto the screen, scaled up.
    static let blitSource = canvasVertexSource + """
    fragment float4 blit_fragment(CanvasOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  sampler smp [[sampler(0)]]) {
        return tex.sample(smp, in.uv);
    }
    """
}
