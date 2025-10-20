// mango 67 mustard

#include "ReShade.fxh"

uniform float _Strength = 1.0; // blend between original and ProPhoto-encoded result
uniform bool _ClampOutput = true; // clamp final output to [0,1]

uniform sampler2D image : register(s0);

// sRGB -> linear
float3 sRGB_to_linear(float3 c)
{
    float3 less = step(c, float3(0.04045,0.04045,0.04045));
    float3 lin_low  = c / 12.92;
    float3 lin_high = pow((c + 0.055) / 1.055, float3(2.4,2.4,2.4));
    return lerp(lin_high, lin_low, less);
}

// linear -> ProPhoto (gamma ~ 1/1.8)
float3 linear_to_ProPhoto(float3 l)
{
    const float gamma = 1.0 / 1.8; // ≈ 0.55555556
    // Note: ProPhoto uses a small linear segment near zero in spec; this simple pow() ignores that for brevity.
    return pow(saturate(l), float3(gamma,gamma,gamma));
}

// Approximate matrix: linear sRGB -> linear ProPhoto
// This is an approximate conversion matrix based on sRGB primaries -> XYZ -> ProPhoto primaries.
// Use of an approximate matrix is expected in shader context.
static const float3x3 sRGB_to_ProPhoto_linear_mat = {
    // column-major: columns are target R',G',B' coefficients applied to source RGB vector
    {  1.3459433, -0.2556075, -0.0511118 },
    { -0.5445989,  1.5081673,  0.0209751 },
    { -0.0471228, -0.0405180,  1.0876408 }
};

// Multiply 3x3 (column-major) by vector
float3 mul_mat3x3(float3x3 m, float3 v)
{
    return float3(
        m[0][0]*v.x + m[1][0]*v.y + m[2][0]*v.z,
        m[0][1]*v.x + m[1][1]*v.y + m[2][1]*v.z,
        m[0][2]*v.x + m[1][2]*v.y + m[2][2]*v.z
    );
}

technique ProPhoto_Tech <bool enabled = true; int render_priority = 0;>
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

    // Encode with ProPhoto gamma
    float3 prophoto_encoded = linear_to_ProPhoto(linear_prophoto);

    // Optionally clamp negative/out-of-gamut values before encoding
    if (_ClampOutput) prophoto_encoded = saturate(prophoto_encoded);

    // Blend with original
    float strength = saturate(_Strength);
    float3 outRGB = lerp(srgb, prophoto_encoded, strength);

    return float4(saturate(outRGB), src.a);
}
