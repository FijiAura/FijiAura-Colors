// ReShade shader: approximate sRGB -> scRGB (linear HDR) processing -> display.
// scRGB is a linear wide-range RGB working space (often floats outside 0..1).
// This shader linearizes sRGB, applies an HDR gain/exposure in scRGB space, then
// optionally applies simple tonemapping and re-encodes for display.
//
// Notes:
// - ReShade framebuffers may be 8-bit; true HDR requires a float/R16G16B16A16 target.
// - This is an approximation for creative use, not a full color-managed scRGB pipeline.

#include "ReShade.fxh"

uniform float _ExposureEV = 0.0;      // exposure change in EV stops (±)
uniform float _Gain = 1.0;            // linear gain in scRGB space
uniform bool  _UseReinhard = true;    // apply simple Reinhard tonemap before output
uniform float _WhitePoint = 1.0;      // white point for Reinhard (1 = default)
uniform float _Strength = 1.0;        // blend between original and processed (0..1)

uniform sampler2D image : register(s0);

// sRGB -> linear
float3 sRGB_to_linear(float3 c)
{
    float3 less = step(c, float3(0.04045,0.04045,0.04045));
    float3 lin_low  = c / 12.92;
    float3 lin_high = pow((c + 0.055) / 1.055, float3(2.4,2.4,2.4));
    return lerp(lin_high, lin_low, less);
}

// linear -> sRGB
float3 linear_to_sRGB(float3 c)
{
    float3 less = step(c, float3(0.0031308,0.0031308,0.0031308));
    float3 srgb_low  = c * 12.92;
    float3 srgb_high = 1.055 * pow(c, float3(1.0/2.4,1.0/2.4,1.0/2.4)) - 0.055;
    return lerp(srgb_high, srgb_low, less);
}

// Simple Reinhard tonemapping: mapped = (color * (1/white^2)) / (1 + color * (1/white^2))
// Using white point to control shoulder
float3 ReinhardTonemap(float3 hdr, float white)
{
    float3 scaled = hdr / (white * white);
    return scaled / (1.0 + scaled);
}

technique scRGB_Tech <bool enabled = true; int render_priority = 0;>
{
    pass
    {
        PixelShader = PS_scRGB;
    }
}

float4 PS_scRGB(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float4 src = tex2D(image, tex);
    float3 srgb = src.rgb;

    // 1) Convert input sRGB -> linear (this is our starting scRGB linear values)
    float3 linear = sRGB_to_linear(srgb);

    // 2) Apply scRGB operations: exposure and gain (scRGB can represent >1.0 and negatives)
    float ev = _ExposureEV;
    float gainFromEV = pow(2.0, ev); // EV stops
    float totalGain = saturate(_Gain) * gainFromEV;

    float3 scLinear = linear * totalGain;

    // 3) (Optional) Tonemap back to displayable range
    float3 toneMapped = scLinear;
    if (_UseReinhard)
        toneMapped = ReinhardTonemap(scLinear, max(0.00001, _WhitePoint));

    // 4) Encode linear -> sRGB for display
    float3 processed = linear_to_sRGB(saturate(toneMapped));

    // 5) Blend with original based on strength
    float s = saturate(_Strength);
    float3 outRGB = lerp(srgb, processed, s);

    return float4(saturate(outRGB), src.a);
}
