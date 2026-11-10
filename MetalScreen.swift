import SwiftUI
import MetalKit

/// Renders the emulator's 240x160 frame with a Metal fragment shader (filters chosen in Settings).
struct MetalScreen: UIViewRepresentable {
    let emu: Emulator

    func makeCoordinator() -> Renderer { Renderer(emu) }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.delegate = context.coordinator
        v.preferredFramesPerSecond = 60
        v.colorPixelFormat = .bgra8Unorm
        v.framebufferOnly = true
        v.isOpaque = true
        v.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.coordinator.setup(v)
        return v
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Renderer: NSObject, MTKViewDelegate {
        private let emu: Emulator
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var tex: MTLTexture?

        init(_ emu: Emulator) { self.emu = emu }

        private struct Uniforms { var mode: Int32; var colorCorrect: Int32; var outSize: SIMD2<Float>; var texSize: SIMD2<Float> }

        func setup(_ view: MTKView) {
            guard let dev = view.device else { return }
            queue = dev.makeCommandQueue()
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 240, height: 160, mipmapped: false)
            td.usage = .shaderRead
            tex = dev.makeTexture(descriptor: td)
            do {
                let lib = try dev.makeLibrary(source: Renderer.shaderSource, options: nil)
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: "vmain")
                d.fragmentFunction = lib.makeFunction(name: "fmain")
                d.colorAttachments[0].pixelFormat = view.colorPixelFormat
                pipeline = try dev.makeRenderPipelineState(descriptor: d)
            } catch { print("Metal setup failed: \(error)") }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline, let tex, let queue,
                  let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
                  let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
            emu.pixels.withUnsafeBytes {
                tex.replace(region: MTLRegionMake2D(0, 0, 240, 160), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 240 * 4)
            }
            let p = SettingsStore.shared.prefs
            var u = Uniforms(mode: Int32(p.filter), colorCorrect: p.colorCorrect ? 1 : 0,
                             outSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                             texSize: SIMD2(240, 160))
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentTexture(tex, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
            cmd.present(drawable)
            cmd.commit()
        }

        // Filter modes: 0 nearest, 1 bilinear, 2 sharp bilinear, 3 LCD grid, 4 scanlines
        static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 pos [[position]]; float2 uv; };
        struct U { int mode; int colorCorrect; float2 outSize; float2 texSize; };

        vertex VOut vmain(uint vid [[vertex_id]]) {
            float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
            VOut o; o.pos = float4(p[vid], 0, 1);
            o.uv = float2((p[vid].x + 1.0) * 0.5, 1.0 - (p[vid].y + 1.0) * 0.5);
            return o;
        }

        fragment float4 fmain(VOut in [[stage_in]], texture2d<float> t [[texture(0)]], constant U &u [[buffer(0)]]) {
            constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
            constexpr sampler linear(filter::linear, address::clamp_to_edge);
            float2 px = in.uv * u.texSize;
            float3 c;
            if (u.mode == 0) {
                c = t.sample(nearest, in.uv).rgb;
            } else if (u.mode == 1) {
                c = t.sample(linear, in.uv).rgb;
            } else if (u.mode == 2) {
                float s = max(floor(min(u.outSize.x / u.texSize.x, u.outSize.y / u.texSize.y)), 1.0);
                float2 region = float2(0.5 - 0.5 / s);
                float2 center = fract(px) - 0.5;
                float2 f = (center - clamp(center, -region, region)) * s + 0.5;
                c = t.sample(linear, (floor(px) + f) / u.texSize).rgb;
            } else if (u.mode == 3) {
                c = t.sample(nearest, in.uv).rgb;
                float2 f = fract(px);
                float g = smoothstep(0.0, 0.18, f.x) * smoothstep(0.0, 0.18, f.y);
                c *= mix(0.55, 1.0, g) * 1.12;
            } else {
                c = t.sample(linear, in.uv).rgb;
                float f = fract(px.y);
                c *= mix(0.6, 1.0, smoothstep(0.0, 0.5, f) * smoothstep(1.0, 0.5, f)) * 1.15;
            }
            if (u.colorCorrect == 1) {
                // Approximation of the GBA's washed-out, slightly cross-talking LCD.
                float3 lin = pow(c, float3(2.2));
                float3x3 m = float3x3(float3(0.82, 0.04, 0.04), float3(0.18, 0.86, 0.14), float3(0.00, 0.10, 0.82));
                c = pow(clamp(m * lin * 1.08, 0.0, 1.0), float3(1.0 / 2.2));
            }
            return float4(clamp(c, 0.0, 1.0), 1.0);
        }
        """
    }
}
