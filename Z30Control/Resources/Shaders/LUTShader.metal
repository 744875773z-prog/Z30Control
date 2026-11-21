//
//  LUTShader.metal
//  Z30Control
//
//  Apple Metal 专业电影监看图形着色器套件：
//  1. 3D LUT 胶片色彩实时映射 (三线性硬件插值与平滑浓度混合)
//  2. Sobel 算子对焦峰值高反差边缘检测 (Focus Peaking)
//  3. 过曝警示斑马纹算法 (Zebra Pattern)
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

// MARK: - 基础顶点着色器
vertex VertexOut lutVertexShader(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = in.position;
    out.texCoords = in.texCoords;
    return out;
}

// MARK: - 1. 3D LUT 胶片色彩映射片元着色器
fragment half4 lutFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<half> sourceTexture [[texture(0)]],
    texture3d<half> lutTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    sampler lutSampler [[sampler(1)]],
    constant float &intensity [[buffer(0)]]
) {
    half4 originalColor = sourceTexture.sample(textureSampler, in.texCoords);
    float3 lutCoord = float3(originalColor.rgb);
    half4 gradedColor = lutTexture.sample(lutSampler, lutCoord);
    half3 finalRGB = mix(originalColor.rgb, gradedColor.rgb, half(intensity));
    return half4(finalRGB, originalColor.a);
}

// MARK: - 2. 电影级对焦峰值边缘检测着色器 (Sobel Focus Peaking)
fragment half4 focusPeakingShader(
    VertexOut in [[stage_in]],
    texture2d<half> sourceTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant float &threshold [[buffer(0)]],      // 峰值灵敏度阈值 (通常 0.15 ~ 0.3)
    constant half3 &peakingColor [[buffer(1)]]     // 峰值高亮色 (尼康绿或荧光黄)
) {
    float2 texelSize = float2(1.0 / sourceTexture.get_width(), 1.0 / sourceTexture.get_height());
    
    // Sobel 3x3 采样周边亮度
    half l00 = dot(sourceTexture.sample(textureSampler, in.texCoords + float2(-1, -1) * texelSize).rgb, half3(0.299, 0.587, 0.114));
    half l10 = dot(sourceTexture.sample(textureSampler, in.texCoords + float2( 0, -1) * texelSize).rgb, half3(0.299, 0.587, 0.114));
    half l20 = dot(sourceTexture.sample(textureSampler, in.texCoords + float2( 1, -1) * texelSize).rgb, half3(0.299, 0.587, 0.114));
    
    half l01 = dot(sourceTexture.sample(textureSampler, in.texCoords + float2(-1,  0) * texelSize).rgb, half3(0.299, 0.587, 0.114));
    half l21 = dot(sourceTexture.sample(textureSampler, in.texCoords + float2( 1,  0) * texelSize).rgb, half3(0.299, 0.587, 0.114));
    
    half l02 = dot(sourceTexture.sample(textureSampler, in.texCoords + float2(-1,  1) * texelSize).rgb, half3(0.299, 0.587, 0.114));
    half l12 = dot(sourceTexture.sample(textureSampler, in.texCoords + float2( 0,  1) * texelSize).rgb, half3(0.299, 0.587, 0.114));
    half l22 = dot(sourceTexture.sample(textureSampler, in.texCoords + float2( 1,  1) * texelSize).rgb, half3(0.299, 0.587, 0.114));
    
    // 梯度计算
    half gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    half gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    half magnitude = sqrt(gx * gx + gy * gy);
    
    half4 baseColor = sourceTexture.sample(textureSampler, in.texCoords);
    if (magnitude > half(threshold)) {
        return half4(peakingColor, 1.0); // 边缘高反差着色
    }
    return baseColor;
}

// MARK: - 3. 过曝斑马条纹着色器 (Zebra Pattern Generator)
fragment half4 zebraPatternShader(
    VertexOut in [[stage_in]],
    texture2d<half> sourceTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant float &zebraThreshold [[buffer(0)]]  // 斑马线亮度阈值 (如 0.90 表示 90% IRE)
) {
    half4 baseColor = sourceTexture.sample(textureSampler, in.texCoords);
    half luminance = dot(baseColor.rgb, half3(0.299, 0.587, 0.114));
    
    if (luminance >= half(zebraThreshold)) {
        // 计算 45 度动态倾斜斜纹
        float stripe = sin((in.position.x + in.position.y) * 0.4);
        if (stripe > 0.0) {
            return half4(0.1, 0.1, 0.1, 1.0); // 黑色斑马纹
        } else {
            return half4(1.0, 1.0, 1.0, 1.0); // 白色斑马纹
        }
    }
    return baseColor;
}
