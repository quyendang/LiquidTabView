#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Capsule-local optical displacement. Center magnifies; the curved rim bends
// neighbouring glyphs more strongly. Sampling is bounded by 24pt per axis.
[[ stitchable ]] half4 liquidLens(float2 p, SwiftUI::Layer layer,
                                  float2 center, float2 radii, float strength) {
    float2 d = p - center;
    float r = length(d / max(radii, float2(1)));
    float rim = smoothstep(0.45, 0.94, r);
    float envelope = 1.0 - smoothstep(0.98, 1.16, r);
    float magnify = 0.12 + 0.18 * rim;
    float2 shift = clamp(-d * magnify * strength * envelope, float2(-22), float2(22));
    float2 dispersion = normalize(d + float2(0.001)) * (0.7 * strength * rim * envelope);
    half4 c = layer.sample(p + shift);
    half4 red = layer.sample(p + shift + dispersion);
    half4 blue = layer.sample(p + shift - dispersion);
    half alpha = max(c.a, max(red.a, blue.a));
    return half4(min(half3(red.r, c.g, blue.b), half3(alpha)), alpha);
}
