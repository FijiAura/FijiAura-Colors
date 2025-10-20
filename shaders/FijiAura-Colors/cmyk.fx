#include "ReShade.fxh"

uniform float4 _Params = float4(1.0, 1.0, 1.0, 1.0); // (C, M, Y, K) multipliers
uniform float _Strength = 1.0; // overall effect strength 0..1
uniform bool _PreserveLuminance = true; // try to keep original luminance

uniform sampler2D image : register(s0);

// Convert RGB (assumed in 0..1) to CMY
float3 RGBtoCMY(float3 rgb)
{
return 1.0 - rgb;
}

// Better K (black) estimate: use amount of neutral black possible:
// K = min(1 - max(R,G,B), min(C,M,Y)) where C/M/Y = 1-R/G/B
float RGBtoK(float3 rgb)
{
float3 cmy = RGBtoCMY(rgb);
float k_from_cmy = min(min(cmy.r, cmy.g), cmy.b);
float k_from_rgb = 1.0 - max(max(rgb.r, rgb.g), rgb.b);
return max(0.0, min(k_from_cmy, k_from_rgb));
}

// Convert CMYK back to RGB using typical subtractive model:
// R = 1 - min(1, C + K)
float3 CMYKtoRGB(float3 cmy, float k)
{
float3 ink = saturate(cmy + float3(k,k,k));
return 1.0 - ink;
}

// Apply ink adjustments: _Params act as multipliers for each ink channel coverage.
float3 ApplyInkAdjust(float3 rgb, float C_adj, float M_adj, float Y_adj, float K_adj)
{
float3 cmy = RGBtoCMY(rgb);
float k = RGBtoK(rgb);

// Multiply coverage, then clamp
cmy.r = saturate(cmy.r * C_adj);
cmy.g = saturate(cmy.g * M_adj);
cmy.b = saturate(cmy.b * Y_adj);
k     = saturate(k        * K_adj);

float3 outRGB = CMYKtoRGB(cmy, k);
return saturate(outRGB);
}

// Preserve luminance: scale chroma of modified color to match original luminance.
// Uses Rec.709 luminance coefficients.
float3 PreserveLuma(float3 orig, float3 modified)
{
const float3 Lw = float3(0.2126, 0.7152, 0.0722);
float origL = dot(orig, Lw);
float modL  = dot(modified, Lw);
if (modL <= 1e-6) return modified; // avoid division by zero
float scale = origL / modL;

// Scale modified color towards luminance-preserved result while keeping ratios.
float3 result = saturate(modified * scale);

return result;
if (modL <= 1e-6) return modified; // avoid division by zero
float scale = origL / modL;

// Scale modified color towards luminance-preserved result while keeping ratios.
float3 result = saturate(modified * scale);

return result;
}

technique CMYK_Tech 
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
float C_param = saturate(_Params.x);
float M_param = saturate(_Params.y);
float Y_param = saturate(_Params.z);
float K_param = saturate(_Params.w);
float s = saturate(_Strength);

float3 modRGB = ApplyInkAdjust(rgb, C_param, M_param, Y_param, K_param);

if (_PreserveLuminance)
    modRGB = PreserveLuma(rgb, modRGB);

float3 finalRGB = lerp(rgb, modRGB, s);

return float4(saturate(finalRGB), col.a);
}
