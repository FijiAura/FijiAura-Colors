// CMYK.fx
// Simple ReShade shader to simulate CMYK-style color adjustments.

// ReShade standard headers
#include "ReShade.fxh"

uniform float4 _Params = float4(1.0, 1.0, 1.0, 1.0); // (C, M, Y, K) defaults
uniform float _Strength = 1.0; // overall effect strength 0..1
uniform bool _PreserveLuminance = true; // try to keep original luminance

uniform sampler2D image : register(s0);

float3 RGBtoCMY(float3 rgb)
{
    // Simple CMY = 1 - RGB
    return 1.0 - rgb;
}

float RGBtoK(float3 rgb)
{
    // K (key/black) approximated as min(C,M,Y)
    float3 cmy = RGBtoCMY(rgb);
    return min(min(cmy.r, cmy.g), cmy.b);
}

float3 CMYKtoRGB(float3 cmy, float k)
{
    // Convert CMYK back to RGB: R = (1 - C) * (1 - K)
    return (1.0 - cmy) * (1.0 - k);
}

float3 ApplyInkAdjust(float3 rgb, float C_adj, float M_adj, float Y_adj, float K_adj)
{
    // Convert to CMY and K
    float3 cmy = RGBtoCMY(rgb);
    float k = RGBtoK(rgb);

    // Apply adjustments: treat adj values as multipliers for ink coverage
    // Clamp to [0,1]
    cmy.r = saturate(cmy.r * C_adj);
    cmy.g = saturate(cmy.g * M_adj);
    cmy.b = saturate(cmy.b * Y_adj);
    k = saturate(k * K_adj);

    // Reconstruct RGB
    float3 outRGB = CMYKtoRGB(cmy, k);

    return outRGB;
}

float3 PreserveLuma(float3 orig, float3 modified)
{
    // Keep original luminance while replacing chroma
    // Using Rec. 709 luminance
    float origL = dot(orig, float3(0.2126, 0.7152, 0.0722));
    float modL  = dot(modified, float3(0.2126, 0.7152, 0.0722));
    if (modL <= 1e-5) return modified;
    float scale = origL / modL;
    return saturate(modified * scale);
}

technique CMYK_Tech <bool enabled = true; int render_priority = 0;>
{
    pass
    {
        PixelShader = PS_CMYK;
    }
}

float4 PS_CMYK(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float4 col = tex2D(image, tex);
    float3 rgb = col.rgb;

    // Parameters from uniform
    float C_param = _Params.x; // default 1.0 = keep original coverage
    float M_param = _Params.y;
    float Y_param = _Params.z;
    float K_param = _Params.w;

    // Ensure safe ranges
    C_param = saturate(C_param);
    M_param = saturate(M_param);
    Y_param = saturate(Y_param);
    K_param = saturate(K_param);
    float s = saturate(_Strength);

    // Apply CMYK ink adjustments
    float3 modRGB = ApplyInkAdjust(rgb, C_param, M_param, Y_param, K_param);

    // Optionally preserve luminance
    if (_PreserveLuminance)
        modRGB = PreserveLuma(rgb, modRGB);

    // Mix with original based on strength
    float3 finalRGB = lerp(rgb, modRGB, s);

    return float4(finalRGB, col.a);
}
