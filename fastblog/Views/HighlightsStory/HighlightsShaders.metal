#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 highlightsPaletteWash(float2 position, half4 color, half4 tint, float intensity) {
    float vertical = clamp(position.y / 1200.0, 0.0, 1.0);
    half blend = half(clamp(intensity, 0.0, 1.0) * (0.35 + vertical * 0.25));
    return mix(color, tint, blend);
}

[[ stitchable ]] float2 highlightsKenBurns(float2 position, float2 size, float progress, float zoomAmount) {
    float2 center = size * 0.5;
    float scale = max(1.0, 1.0 + clamp(progress, 0.0, 1.0) * max(0.0, zoomAmount));
    return center + ((position - center) / scale);
}
