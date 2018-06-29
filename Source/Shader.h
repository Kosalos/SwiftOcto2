#pragma once
#include <simd/simd.h>

#ifdef SHADER
    #define CC constant
    typedef simd::float2 simd_float2;
    typedef simd::float3 simd_float3;
    typedef simd::float4 simd_float4;
    typedef simd::float4x4 simd_float4x4;
    typedef metal::uchar u_char;
#else
    #define CC
#endif

typedef struct {
	simd_float3 pos;
	simd_float3 nrm;
	simd_float2 txt;
    simd_float4 color;
    u_char drawStyle;
} TVertex;

typedef struct {
    simd_float4x4 mvp;
    u_char drawStyle;
    simd_float3 light;

    simd_float4 unused1;
    simd_float4 unused2;
} ConstantData;
