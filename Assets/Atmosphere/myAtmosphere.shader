Shader "CasualAtmosphere/myAtmosphere" {
    Properties { }

    SubShader {
        // Cull Off
        // ZWrite Off
        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            //#include "Helper.hlsl"
            
            float SeaLevel;
            float GroundRadius;
            float AtmosphereHeight;

            float3 SunLightColor;
            float SunDiskAngle;
            float SunLightIntensity;

            Texture2D _TransmittanceLut;
            Texture2D _SkyViewLut;

            struct a2v {
                float4 positionOS : POSITION;
            };

            struct v2f {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;//SEMANTIC_HELLO_WORLD
            };

            float RayIntersectSphere(float3 center, float radius, float3 rayStart, float3 rayDir) {
                float OS = length(center - rayStart);
                float SH = dot(center - rayStart, rayDir);
                float OH = sqrt(OS * OS - SH * SH);
                float PH = sqrt(radius * radius - OH * OH);

                if (OH > radius) return -1;

                float t1 = SH - PH;
                float t2 = SH + PH;
                float t = (t1 < 0) ? t2 : t1;
                return t;
            }

            float2 GetTransmittanceLutUv(float bottomRadius, float topRadius, float mu, float r) {
                // 映射r高度： H（切边长度）
                float Hmax = sqrt(max(0.0f, topRadius * topRadius - bottomRadius * bottomRadius));
                float Hcurr = sqrt(max(0.0f, r * r - bottomRadius * bottomRadius));
                float x_r = Hcurr / Hmax;

                float d_min = topRadius - r;
                float d_max = Hcurr + Hmax;
                float discriminant = r * r * (mu * mu - 1.0f) + topRadius * topRadius;
                float d = max(0.0f, (-r * mu + sqrt(discriminant)));
                float x_mu = (d - d_min) / (d_max - d_min);

                return float2(x_mu, x_r);
            }
            // 查表计算任意点 p 沿着任意方向 dir 到大气层边缘的 transmittance
            float3 TransmittanceToAtmosphere(float3 p, float3 dir) {
                float bottomRadius = GroundRadius;
                float topRadius = GroundRadius + AtmosphereHeight;

                float3 upVector = normalize(p);
                float cos_theta = dot(upVector, dir);
                float r = length(p);

                float2 uv = GetTransmittanceLutUv(bottomRadius, topRadius, cos_theta, r);
                return _TransmittanceLut.SampleLevel(sampler_LinearClamp, uv, 0).rgb;
            }

            float2 ViewDirToUV(float3 v) {
                float2 uv = float2(atan2(v.z, v.x), asin(v.y));
                uv /= float2(2.0 * PI, PI);
                uv += float2(0.5, 0.5);

                return uv;
            }
            float3 GetSunDisk(float3 eyePos, float3 viewDir, float3 lightDir) {
                // 计算入射光照
                float cosine_theta = dot(viewDir, lightDir);
                float theta = acos(cosine_theta) * (180.0 / PI);

                // 判断光线是否被星球阻挡
                float disToPlanet = RayIntersectSphere(float3(0, 0, 0), GroundRadius, eyePos, viewDir);
                if (disToPlanet >= 0) return float3(0, 0, 0);

                float disToAtmosphere = RayIntersectSphere(float3(0, 0, 0), GroundRadius + AtmosphereHeight, eyePos, viewDir);
                if (disToAtmosphere < 0) return float3(0, 0, 0);

                // 计算衰减
                float3 hitPoint = eyePos + viewDir * disToAtmosphere;
                
                float3 sunLuminance = SunLightColor * SunLightIntensity;
                sunLuminance *= TransmittanceToAtmosphere(eyePos, viewDir);
                if (theta < SunDiskAngle) return sunLuminance;
                
                return float3(0, 0, 0);
            }
            v2f vert(a2v i) {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                o.positionWS = TransformObjectToWorld(i.positionOS.xyz);
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                float4 color = float4(0, 0, 0, 1);

                Light mainLight = GetMainLight();
                float3 lightDir = mainLight.direction; //指向太阳的方向
                float3 viewDir = normalize(i.positionWS);
                float h = _WorldSpaceCameraPos.y - SeaLevel + GroundRadius;
                float3 eyePos = float3(0, h, 0);
                color.rgb += GetSunDisk(eyePos, viewDir, lightDir);
                
                color.rgb += SAMPLE_TEXTURE2D(_SkyViewLut, sampler_LinearClamp, ViewDirToUV(viewDir)).rgb;
                return color;
            }
            ENDHLSL
        }
    }
}
