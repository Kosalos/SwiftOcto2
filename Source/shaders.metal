#define SHADER

#include <metal_stdlib>
#import <simd/simd.h>
#include "Shader.h"

using namespace metal;

struct Transfer {
    float4 position [[position]];
    float pointsize [[point_size]];
    float2 txt;
    float4 color;
    float4 lighting;
    uchar drawStyle;
};

vertex Transfer texturedVertexShader(
    device TVertex* vData [[ buffer(0) ]],
    constant ConstantData& constantData [[ buffer(1) ]],
    unsigned int vid [[ vertex_id ]])
{
    Transfer out;
    TVertex v = vData[vid];
    
    out.pointsize = 10.0;       // target and IK nodes are drawn as points
    out.txt = v.txt;
    out.color = v.color;
    out.drawStyle = v.drawStyle;
    out.position = constantData.mvp * float4(v.pos, 1.0);
    
    if(v.drawStyle == 1) {
        float4 amb = float4(0.86,0.86,0.86,1);
        float3 nrm = vData[vid].nrm;
        float n_dot_l = dot(nrm.rgb,constantData.light);
        n_dot_l = fmax(0.0, n_dot_l);
        out.lighting = amb + n_dot_l;
    }

    return out;
}

fragment float4 texturedFragmentShader(
    Transfer data [[stage_in]],
    texture2d<float> tex2D [[texture(0)]],
    sampler sampler2D [[sampler(0)]])
{
    if(data.drawStyle == 0) return data.color;
    return tex2D.sample(sampler2D, data.txt.xy) * data.lighting;
}
