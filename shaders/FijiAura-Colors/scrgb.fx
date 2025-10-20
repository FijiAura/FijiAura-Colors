#include "ReShade.fxh"

uniform float _ExposureEV = 0.0;      // exposure change in EV stops (±)
uniform float _Gain = 1.0;            // linear gain in scRGB space (can be >1)
uniform bool  _UseReinhard = true;    // apply simple Reinhard tonemap before output
uniform float _WhitePoint = 1.0;      // white point for Reinhard (1 = default)
uniform float _Strength = 1.0;        // blend between original and processed (0..1)

uniform sampler2D image : register(s0);

// sRGB -> linear
float3 sRGB_to_linear(float3 c)
{
// if c <= 0.04045 -> c/12.92 else pow((c+0.055)/1.055, 2.4)
float3 le = step(c, float3(0.04045,0.04045,0.04045)); // 1 where c <= 0.04045
float3 low  = c / 12.92;
float3 high = pow((c + 0.055) / 1.055, float3(2.4,2.4,2.4));
return lerp(high, low, le); // choose low when le == 1
}

// linear -> sRGB
float3 linear_to_sRGB(float3 c)
{
// clamp small negatives to 0 to avoid pow on negative values
c = max(c, 0.0);
// if c <= 0.0031308 -> c*12.92 else 1.055*pow(c,1/2.4)-0.055
float3 le = step(c, float3(0.0031308,0.0031308,0.0031308));
float3 low  = c * 12.92;
float3 high = 1.055 * pow(c, float3(1.0/2.4,1.0/2.4,1.0/2.4)) - 0.055;
return lerp(high, low, le);
}

// Simple Reinhard tonemapping with white point
float3 ReinhardTonemap(float3 hdr, float white)
{
// Clamp white to tiny positive to avoid division by zero
white = max(white, 1e-6);
float3 scaled = hdr / (white * white);
return scaled / (1.0 + scaled);
}

technique scRGB_Tech 
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
// 1) Convert sRGB -> linear (start of scRGB linear domain)
float3 linear = sRGB_to_linear(srgb);

// 2) Apply scRGB operations: exposure and gain (scRGB can represent >1.0)
float gainFromEV = pow(2.0, _ExposureEV); // EV stops
float totalGain = _Gain * gainFromEV;    // allow >1 gains; user controls _Gain

float3 scLinear = linear * totalGain;

// 3) Optional tonemap
float3 toneMapped = scLinear;
if (_UseReinhard)
    toneMapped = ReinhardTonemap(scLinear, _WhitePoint);

// 4) Encode linear -> sRGB for display (clamp to [0,1] only on final encoded colors)
float3 processed = linear_to_sRGB(toneMapped);

// 5) Blend with original based on strength (blend in encoded sRGB space as originally)
float s = saturate(_Strength);
float3 outRGB = lerp(srgb, processed, s);

return float4(saturate(outRGB), src.a);
}
