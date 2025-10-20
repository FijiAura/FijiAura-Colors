#include "ReShade.fxh"

uniform float _Strength = 1.0; // blend between original and AdobeRGB-encoded result

uniform sampler2D image : register(s0);

// sRGB -> linear
float3 sRGB_to_linear(float3 c)
{
// For each channel: if c <= 0.04045 -> c/12.92 else pow((c+0.055)/1.055, 2.4)
float3 less = step(c, float3(0.04045,0.04045,0.04045)); // 1.0 where c <= 0.04045
float3 lin_low  = c / 12.92;
float3 lin_high = pow((c + 0.055) / 1.055, float3(2.4,2.4,2.4));
return lerp(lin_high, lin_low, less); // when less==1 -> lin_low, else lin_high
}

// linear -> Adobe RGB (1998) gamma (gamma = 1/2.19921875 -> raise to 1/2.19921875)
float3 linear_to_AdobeRGB(float3 l)
{
const float gamma = 1.0 / 2.19921875; // ≈ 0.454706927
return pow(saturate(l), float3(gamma,gamma,gamma));
}

// sRGB linear -> Adobe RGB linear conversion matrix (row-major).
// This matrix is an approximate direct mapping from linear sRGB (D65) to linear Adobe RGB (D65).
// Values chosen such that result color stays in gamut as much as possible.
static const float3x3 sRGB_to_AdobeRGB_linear_mat = {
{ 1.0478112,  0.0228866, -0.0501270 }, // row 0
{ 0.0295424,  0.9904844, -0.0170491 }, // row 1
{-0.0092345,  0.0150436,  0.7519885 }  // row 2
};

// Multiply row-major 3x3 matrix by vector
float3 mul_mat3x3(float3x3 m, float3 v)
{
return float3(
dot(m[0], v),
dot(m[1], v),
dot(m[2], v)
);
}

technique AdobeRGB_Tech 
{
pass
{
PixelShader = PS_AdobeRGB;
}
}

float4 PS_AdobeRGB(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
float4 src = tex2D(image, tex);
float3 srgb = src.rgb;
// Convert sRGB -> linear
float3 linear_srgb = sRGB_to_linear(srgb);

// Transform linear sRGB -> linear Adobe RGB (approx)
float3 linear_adobe = mul_mat3x3(sRGB_to_AdobeRGB_linear_mat, linear_srgb);

// Apply Adobe RGB gamma
float3 adobe_encoded = linear_to_AdobeRGB(linear_adobe);

// Blend with original (in sRGB space). If you prefer blending in linear space, convert accordingly.
float strength = saturate(_Strength);
float3 outRGB = lerp(srgb, adobe_encoded, strength);

return float4(saturate(outRGB), src.a);
}
