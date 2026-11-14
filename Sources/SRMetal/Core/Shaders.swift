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
        // Exact maths, so the classic look rounds dot positions the same way the original did.
        options.mathMode = .safe
        return try device.makeLibrary(source: source, options: options)
    }

    static func function(_ name: String, in library: MTLLibrary) throws -> MTLFunction {
        guard let function = library.makeFunction(name: name) else {
            throw ShaderError.missingFunction(name)
        }
        return function
    }

    /// Copies the small classic-look picture onto the screen, scaled up.
    static let blitSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct BlitOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex BlitOut blit_vertex(uint vid [[vertex_id]]) {
        // One oversized triangle that covers the whole viewport.
        float2 p = float2((vid << 1) & 2, vid & 2);
        BlitOut out;
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        out.uv = float2(p.x, 1.0 - p.y);
        return out;
    }

    fragment float4 blit_fragment(BlitOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  sampler smp [[sampler(0)]]) {
        return tex.sample(smp, in.uv);
    }
    """
}
