#include "ReShade.fxh"

uniform float _Strength = 1.0; // blend between original and ProPhoto-encoded result
uniform bool _ClampOutput = true; // clamp final output to [0,1]

uniform sampler2D image : register(s0);

// sRGB -> linear
float3 sRGB_to_linear(float3 c)
{
// if c <= 0.04045 -> c/12.92 else pow((c+0.055)/1.055, 2.4)
float3 less = step(c, float3(0.04045,0.04045,0.04045)); // 1 where c <= 0.04045
float3 lin_low  = c / 12.92;
float3 lin_high = pow((c + 0.055) / 1.055, float3(2.4,2.4,2.4));
return lerp(lin_high, lin_low, less); // chooses lin_low when less == 1
}

// linear -> ProPhoto (approx gamma = 1/1.8)
// Note: real ProPhoto has a small linear toe near zero; this uses a simple power function.
float3 linear_to_ProPhoto(float3 l)
{
const float gamma = 1.0 / 1.8; // ≈ 0.55555556
return pow(saturate(l), float3(gamma,gamma,gamma));
}

// Approximate matrix: linear sRGB -> linear ProPhoto
// Use row-major layout (each row is coefficients for resulting R,G,B).
static const float3x3 sRGB_to_ProPhoto_linear_mat = {
{  1.3459433, -0.2556075, -0.0511118 }, // row 0
{ -0.5445989,  1.5081673,  0.0209751 }, // row 1
{ -0.0471228, -0.0405180,  1.0876408 }  // row 2
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

technique ProPhoto_Tech 
{
pass
{
PixelShader = PS_ProPhoto;
}
}

float4 PS_ProPhoto(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
float4 src = tex2D(image, tex);
float3 srgb = src.rgb;
// Convert sRGB -> linear
float3 linear_srgb = sRGB_to_linear(srgb);

// Convert linear sRGB -> linear ProPhoto (approx)
float3 linear_prophoto = mul_mat3x3(sRGB_to_ProPhoto_linear_mat, linear_srgb);

// Optional clamp pre-encoding to avoid NaNs from negative values
if (_ClampOutput) linear_prophoto = max(linear_prophoto, 0.0);

// Encode with ProPhoto gamma
float3 prophoto_encoded = linear_to_ProPhoto(linear_prophoto);

// Optionally clamp encoded values
if (_ClampOutput) prophoto_encoded = saturate(prophoto_encoded);

// Blend with original (encoded sRGB). For color correctness consider blending in linear space.
float strength = saturate(_Strength);
float3 outRGB = lerp(srgb, prophoto_encoded, strength);

return float4(saturate(outRGB), src.a);
}
