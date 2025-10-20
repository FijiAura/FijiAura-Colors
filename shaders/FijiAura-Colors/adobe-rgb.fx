// yay the include :)

#include "ReShade.fxh"

uniform float _Strength = 1.0; // blend between original and AdobeRGB-encoded result

uniform sampler2D image : register(s0);

// sRGB -> linear
float3 sRGB_to_linear(float3 c)
{
    float3 less = step(c, float3(0.04045,0.04045,0.04045));
    float3 lin_low  = c / 12.92;
    float3 lin_high = pow((c + 0.055) / 1.055, float3(2.4,2.4,2.4));
    return lerp(lin_high, lin_low, less);
}

// linear -> Adobe RGB (1998) gamma (gamma = 1/2.19921875 -> raise to 1/2.19921875)
float3 linear_to_AdobeRGB(float3 l)
{
    const float gamma = 1.0 / 2.19921875; // ≈ 0.454706927
    return pow(saturate(l), float3(gamma,gamma,gamma));
}

// sRGB linear -> Adobe RGB linear conversion matrix
// Matrix converts linear sRGB (D65) to linear Adobe RGB (D65) by first converting to XYZ then to Adobe RGB.
// We can use a single 3x3 matrix approximate for sRGB linear -> Adobe RGB linear.
// Values from common references (sRGB->XYZ and XYZ->AdobeRGB combined).
static const float3x3 sRGB_to_AdobeRGB_linear_mat = {
    { 0.576700, 0.185556, 0.188212 },   // R' column
    { 0.297361, 0.627355, 0.075284 },   // G' column
    { 0.027032, 0.070687, 0.991248 }    // B' column
};
// Note: Matrix above maps linear sRGB to linear Adobe RGB approximately.

// Apply 3x3 matrix (column-major as written)
float3 mul_mat3x3(float3x3 m, float3 v)
{
    return float3(
        m[0][0]*v.x + m[1][0]*v.y + m[2][0]*v.z,
        m[0][1]*v.x + m[1][1]*v.y + m[2][1]*v.z,
        m[0][2]*v.x + m[1][2]*v.y + m[2][2]*v.z
    );
}

technique AdobeRGB_Tech <bool enabled = true; int render_priority = 0;>
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

    // Blend with original
    float strength = saturate(_Strength);
    float3 outRGB = lerp(srgb, adobe_encoded, strength);

    return float4(saturate(outRGB), src.a);
}
