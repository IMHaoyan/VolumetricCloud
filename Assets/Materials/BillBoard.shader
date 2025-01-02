Shader "Haoyan/BillBoard"
{
    Properties
    {
        _BaseColor ("Color", Color) = (1, 1, 1, 1)
        _BaseMap ("MainTex", 2D) = "white" { }
        [Enum(Spherical, 0, CylinDrical, 1)]_BillboardMode ("BillboardMode", int) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque" "Queue" = "AlphaTest" "DisableBatching" = "True"
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_VerticalProfileLut);
            SAMPLER(sampler_VerticalProfileLut);
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float fogCoord : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CBUFFER_START(UnityPerMaterial)
                uniform float4 _BaseColor;
                uniform float4 _BaseMap_ST;
                uniform float _BillboardMode;
            CBUFFER_END

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                //计算新的Billboard顶点位置和法线

                //1.构建视口空间下的旋转矩阵 2.模式切换
                //UNITY_MATRIX_V[1].xyz == world space camera Up unit vector
                float3 upCamVec = lerp(normalize(UNITY_MATRIX_V._m10_m11_m12), float3(0, 1, 0), _BillboardMode);
                //UNITY_MATRIX_V[2].xyz == -1 * world space camera Forward unit vector
                float3 forwardCamVec = -normalize(UNITY_MATRIX_V._m20_m21_m22);
                //UNITY_MATRIX_V[0].xyz == world space camera Right unit vector
                float3 rightCamVec = normalize(UNITY_MATRIX_V._m00_m01_m02);
                float4x4 rotationCamMatrix = float4x4(rightCamVec, 0, upCamVec, 0, forwardCamVec, 0, 0, 0, 0, 1);
                //转换法线和切线
                v.normalOS = normalize(mul(float4(v.normalOS, 0), rotationCamMatrix)).xyz;
                v.tangentOS.xyz = normalize(mul(float4(v.tangentOS.xyz, 0), rotationCamMatrix)).xyz;
                //求出缩放值,前三行三列的每一列的向量长度分别对应X,Y,Z三个轴向的缩放值
                v.positionOS.x *= length(UNITY_MATRIX_M._m00_m10_m20);
                v.positionOS.y *= length(UNITY_MATRIX_M._m01_m11_m21);
                v.positionOS.z *= length(UNITY_MATRIX_M._m02_m12_m22);
                //在固定坐标系下面，我们用左乘的方法；在非固定的坐标系下面，用右乘。
                // v.positionOS = mul(v.positionOS, rotationCamMatrix);
                v.positionOS = v.positionOS.x * rotationCamMatrix._m00_m01_m02_m03 + v.positionOS.y * rotationCamMatrix.
                    _m10_m11_m12_m13
                    + v.positionOS.z * rotationCamMatrix._m20_m21_m22_m23 + v.positionOS.w * rotationCamMatrix.
                    _m30_m31_m32_m33;
                //最后一列是模型中心的世界坐标,加上的是齐次坐标的偏移值,不加都会在原点
                v.positionOS.xyz += UNITY_MATRIX_M._m03_m13_m23;
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.positionCS = TransformWorldToHClip(v.positionOS.xyz);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                half4 finalColor;
                //finalColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                finalColor = SAMPLE_TEXTURE2D(_VerticalProfileLut, sampler_VerticalProfileLut, i.uv);
                //clip(finalColor.a - 0.5);
                //finalColor.rgb = MixFog(finalColor.rgb, i.fogCoord);
                return finalColor;
                return finalColor * _BaseColor;
            }
            ENDHLSL

        }
        //UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
    }
}