Shader "URPCustom/Volume/myRayMarching"
{
    Properties
    {
        [HideInInspector]_MainTex ("MainTex", 2D) = "white" { }
        [HideInInspector]_ZFar ("ZFar", Float) = 1.0

        _CloudHeightRange ("_CloudHeightRange", Vector) = (1500, 4000, 0, 8000)
        _stratusInfo ("_stratusInfo", Vector) = (0, 0, 0, 0)
        _cumulusInfo ("_cumulusInfo", Vector) = (0, 0, 0, 0)

        _WeatherTex ("WeatherTex", 2D) = "white" { }

        _cloudCovery ("_cloudCovery", Range(0, 20)) = 1
        _densityMultiplier ("densityMultiplier", Range(0, 0.1)) = 0.1

        [Toggle]_debugShape ("debugShape ", Float) = 0
        [IntRange]_debugShapeFlag ("flag", Range(0, 3)) = 0


        _ShapeTex ("ShapeTex", 3D) = "white" { }
        _baseShapeDetailEffect ("_baseShapeDetailEffect", Range(0, 1)) = 0.5


        _DetailShapeTex ("DetailShapeTex", 3D) = "white" { }
        _detailEffect ("_detailEffect", Range(0, 1)) = 0.5

        [KeywordEnum(ON, OFF)] _INTERPO ("_interpolatedRayON", Float) = 0

        _windDirection ("_WindDirection", Vector) = (0, 0, 0, 0)
        _windSpeed ("_WindSpeed ", Float) = 1

        _display0 ("---------------LightMarching-------------------", Int) = 1
        _MaxStepSize ("MaxStepSize", Float) = 0.5
        [Toggle]_showTruncation ("_showTruncation ", Float) = 1
        _LoopCount ("LoopCount", Float) = 25

        [Toggle]_AdaptiveMarch ("AdaptiveMarch ", Float) = 1

        _albedo ("Albedo", Range(0, 1.0)) = 0.9
        _sigma_t ("Sigma_t", Range(0, 1.0)) = 0.3
        _DirectLightMultiplier ("_DirectLightMultiplier", Range(0.0001, 10.0)) = 1

        [IntRange]_octaves ("_octaves", Range(1, 16)) = 1

        _BlueNoiseTex ("_BlueNoiseTex", 2D) = "white" { }
        _BlueNoiseStrength ("BlueNoiseStrength", Range(0, 20)) = 1
        [Toggle]_DitheringON ("_DitheringON", Float) = 0
        _display0 ("------------------Phase----------------------", Int) = 1
        [Toggle]_usePhase ("_usePhase ", Float) = 1
        [IntRange]_chosePhase ("_chosePhase", Range(0, 2)) = 0
        _g1 ("_g1(反向)", Range(-1, 0)) = -0.5
        _g2 ("_g2(正向)", Range(0, 1.0)) = 0.5

        _blendG ("blendG", Range(0, 1.0)) = 0.5

        [IntRange]_embientON ("_embientON(0:OFF / 2:ON) ", Range(0, 2)) = 0
        _embientColor ("_embientColor", Color) = (1, 1, 1, 1)
        _AmbinetScale0 ("_AmbinetScale0 ", Range(0.000001, 1)) = 0.35
        _AmbinetScale1 ("_AmbinetScale1 ", Range(0.000001, 2)) = 0.5
        _ambientlerp ("_ambientlerp", Range(0, 1)) = 0
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"
        }
        LOD 100

        Cull Off
        ZWrite Off
        ZTest Always

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Help.hlsl"
        #define DensityEPS 0.00001f
        #define _DEBUGMODE 1
        #define EarthRadius 6300000.0

        float _ambientlerp;
        float4 _ShapeNoise_ST;

        float _AmbinetScale1;
        float _AmbinetScale0;

        //-----------------------------------------------------------------------------------
        // float _radius;
        // float3 _position;
        // float _sig_a;
        // float _sig_s;
        // float _powdensity;
        // float _densityMul;
        // float _showDensity;
        // float _stepCount;
        //------------------------------------------------------------------------------------
        ENDHLSL

        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward" "RenderType" = "Overlay"
            }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _INTERPO_ON
            //#pragma multi_compile _ _TEST_ON

            struct a2v
            {
                float4 positionOS : POSITION;
                float2 texcoord : TEXCOORD;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 interpolatedRay : TEXCOORD1;
            };

            float SampleCloudDensity(float3 currentPos)
            {
                float heightFraction = Remap(currentPos.y, _CloudHeightRange.x, _CloudHeightRange.y, 0, 1);

                //添加风的影响
                _windDirection = normalize(_windDirection.xyz);
                float3 wind = _windDirection * _windSpeed * _Time.y;
                float3 dsiPos = currentPos;
                currentPos = currentPos + wind * 1000;

                //采样天气纹理，默认1000km平铺， r 密度, g 吸收率, b 云类型(0~1 => 层云~积云)
                float2 weatherTexUV = dsiPos.xz * _WeatherTex_ST.x; //* _weatherTexTiling;  10.8
                float4 weatherData = SAMPLE_TEXTURE2D_LOD(_WeatherTex, sampler_WeatherTex,
                                                          weatherTexUV * 0.000001 + _WeatherTex_ST.zw + wind.xz * 0.01,
                                                          0);
                weatherData.r *= _cloudCovery;

                #if _DEBUGMODE
                if (_debugShape == 1 && _debugShapeFlag == 0)
                {
                    //WeatherMap
                    return weatherData.r * _densityMultiplier;
                }
                #endif

                //计算云类型密度, w通道为feather的比例
                float stratusDensity = GetCloudTypeDensity(heightFraction, _stratusInfo.x, _stratusInfo.y,
                                                           _stratusInfo.w);
                float cumulusDensity = GetCloudTypeDensity(heightFraction, _cumulusInfo.x, _cumulusInfo.y,
                                                           _cumulusInfo.w);
                float cloudTypeDensity = lerp(stratusDensity, cumulusDensity, weatherData.b);

                #if _DEBUGMODE
                if (_debugShape == 1 && _debugShapeFlag == 1)
                {
                    //CloudType
                    return weatherData.r * cloudTypeDensity * _densityMultiplier;
                }
                #endif

                float3 shapeTexUV = currentPos * _ShapeTex_ST.x * 0.0001;
                float4 shapeTexData = SAMPLE_TEXTURE3D_LOD(_ShapeTex, sampler_ShapeTex, shapeTexUV, 0);

                #if 1
                //Nubis's Method (WeatherMap)
                float fbm = dot(shapeTexData.gba, float3(0.625, 0.25, 0.125)); //添加细节纹理
                float baseShape = Remap(shapeTexData.r, -(1 - fbm) * _baseShapeDetailEffect, 1.0, 0, 1.0);
                float dimensionalProfile = weatherData.r * cloudTypeDensity;
                return saturate(baseShape - (1 - dimensionalProfile)) * _densityMultiplier;
                #else
            float fbm = dot(shapeTexData.gba, float3(0.5, 0.25, 0.125));//添加细节纹理
            float baseShape = Remap(shapeTexData.r, saturate((1 - fbm) * _baseShapeDetailEffect), 1.0, 0, 1.0);
            
            float cloudDensity = baseShape * weatherData.r * cloudTypeDensity ;

            if (_debugShape == 1 && _debugShapeFlag == 2) {
                return cloudDensity * _densityMultiplier * 0.1;
            }

            //细节噪声受风影响，添加向上的偏移
            currentPos += (_windDirection + float3(0, 0.1, 0)) * _windSpeed * _Time.y * 0.1;
            float3 detailTex = SAMPLE_TEXTURE3D_LOD(_DetailShapeTex, sampler_DetailShapeTex, currentPos * _DetailShapeTex_ST.x * 0.0001, 0).rgb;
            float detailTexFBM = dot(detailTex, float3(0.5, 0.25, 0.125));
            //根据高度从纤细到波纹的形状进行变化
            float detailNoise = detailTexFBM;//lerp(detailTexFBM, 1.0 - detailTexFBM,saturate(heightFraction * 1.0));
            //通过使用remap映射细节噪声，可以保留基本形状，在边缘进行变化
            cloudDensity = Remap(cloudDensity, detailNoise * _detailEffect, 1.0, 0.0, 1.0);
            cloudDensity = cloudDensity < 0 ? 0 : cloudDensity;
            return cloudDensity * _densityMultiplier * 0.1;
                #endif
            }

            float3 lightmarchEarth(float3 position, float dstTravelled)
            {
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);

                float3 cameraPos = _WorldSpaceCameraPos;
                float3 EarthCenter = float3(cameraPos.x, -EarthRadius, cameraPos.z);
                //未考虑遮挡, 所以没有用到dstTravelled
                float dstInsideSphere = RayCloudLayerDst(EarthCenter, EarthRadius, _CloudHeightRange.x,
                                                         _CloudHeightRange.y,
                                                         position, lightDir, false).y;

                float stepSize = dstInsideSphere / 8;

                // 计算椎体的偏移，在-(1,1,1)和+(1,1,1)之间使用了六个噪声结果作为Kernel
                static float3 noise_kernel[6] = {
                    float3(0.38051305, 0.92453449, -0.02111345),
                    float3(-0.50625799, -0.03590792, -0.86163418),
                    float3(-0.32509218, -0.94557439, 0.01428793),
                    float3(0.09026238, -0.27376545, 0.95755165),
                    float3(0.28128598, 0.42443639, -0.86065785),
                    float3(-0.16852403, 0.14748697, 0.97460106)
                };

                float tau = 0;
                for (int step = 0; step < 8; step++)
                {
                    position += lightDir * stepSize; //向灯光步进
                    tau += SampleCloudDensity(position) * stepSize; //步进的时候采样噪音累计受灯光影响密度
                }

                float light_attenuation = Beer(tau, _sigma_t);
                float3 lightColor = mainLight.color;
                //lightColor = SampleSH(mainLight.direction);
                // lightColor = half3(1,0,0);
                return lightColor * light_attenuation;
            }

            float3 Scattering(float tau, float cos, float3 Li, float stepsize, float density)
            {
                float Attenuation = 0.5;
                float Contribution = 0.5;
                float PhaseAttenuation = 0.5;

                float3 luminance = 0;
                float g = _g2; //0.5
                float a = 1, b = 1, c = 1;
                [loop]
                for (int n = 0; n < _octaves; n++)
                {
                    float _sigma_s = _albedo * _sigma_t;
                    //ambient light
                    if (n == 0 && _embientON != 0)
                    {
                        //_embientColor.rgb = SampleSH(GetMainLight().direction).rgb;
                        float3 luminance0 = _sigma_s * _embientColor * b * Beer(tau, a * _sigma_t) * pow(
                                1 - density, 0.5) *
                            density * _AmbinetScale0;
                        float3 luminance1 = _sigma_s * _embientColor * b * Beer(tau, a * _sigma_t) * pow(
                                1 - density, 0.5) *
                            0.003 * _AmbinetScale1;
                        luminance += lerp(luminance0, luminance1, _ambientlerp);
                        if (_embientON == 1)
                        {
                            return luminance;
                        }
                    }
                    //directLight
                    luminance += _DirectLightMultiplier * (_sigma_s * density) * b * Li * phase(cos, g * c) * Beer(
                        tau, a * _sigma_t);
                    a *= Attenuation;
                    b *= Contribution;
                    c *= (1 - PhaseAttenuation);
                }
                return luminance;
            }

            float4 cloudRayMarchingEarth(float3 startPoint, float3 direction, float dstToCloud, float inCloudMarchLimit,
                                         float2 uv)
            {
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float cosAngle = dot(direction, lightDir);
                float tau = 0.0;
                float transmittance = 1.0;

                int maxLoopCount = _LoopCount;
                float stepsize = min(inCloudMarchLimit / maxLoopCount, _MaxStepSize);
                if (stepsize == _MaxStepSize)
                {
                    //stepsize如果过大，会过于有层次感，标记出步进长度使用最大限制值的情况，此时使用maxstepsize
                    if (_showTruncation == 0)
                        return float4(float3(1, 0, 0), Beer(tau, _sigma_t));
                }

                float blueNoise = SAMPLE_TEXTURE2D_LOD(_BlueNoiseTex, sampler_BlueNoiseTex, uv * _BlueNoiseTex_ST.xy, 0)
                    .r;
                if (_DitheringON == 1)
                    startPoint += (direction * stepsize) * blueNoise * _BlueNoiseStrength;
                float3 currentPos = startPoint + direction * dstToCloud;

                float inCloudMarchedLength = 0;
                float3 cloudColor = float3(0, 0, 0);


                //一开始大步长进行步进(2倍步长)进行密度采样检测，当检测到云时，退回，进行正常云的采样
                //当累计采样到一定次数0密度时，再切换成大步进
                float densityTest = 0; //云测试密度
                float densityPrevious = 0; //上一次采样密度
                int densitySampleCount_zero = 0; //0密度采样次数

                for (int i = 0; i < maxLoopCount; i++)
                {
                    if (_AdaptiveMarch && densityTest < DensityEPS)
                    {
                        //如果步进到被物体遮挡,或穿出云覆盖范围时,跳出循环
                        if (inCloudMarchedLength >= inCloudMarchLimit)
                        {
                            break;
                        }
                        //向观察方向步进4倍的长度
                        inCloudMarchedLength += 4 * stepsize;
                        currentPos += direction * 4 * stepsize;

                        //进行密度采样，测试是否继续大步前进
                        float currentDensity = SampleCloudDensity(currentPos);
                        densityTest = currentDensity;

                        //如果检测到云，往后退一步(因为我们可能错过了开始位置)
                        if (densityTest > DensityEPS)
                        {
                            inCloudMarchedLength -= 4 * stepsize;
                            currentPos -= direction * 4 * stepsize;
                        }
                    }
                    else
                    {
                        if (inCloudMarchedLength >= inCloudMarchLimit)
                        {
                            break;
                        }
                        inCloudMarchedLength += stepsize;
                        currentPos += direction * stepsize;

                        float currentDensity = SampleCloudDensity(currentPos);

                        if (_AdaptiveMarch && currentDensity < DensityEPS && densityPrevious < DensityEPS)
                        {
                            densitySampleCount_zero++;
                            if (densitySampleCount_zero >= 8)
                            {
                                //切换到大步进
                                densityTest = 0;
                                densitySampleCount_zero = 0;
                                continue;
                            }
                        }

                        if (currentDensity < DensityEPS)
                        {
                            continue;
                        }

                        tau += currentDensity * stepsize;

                        transmittance = Beer(tau, _sigma_t);

                        if (transmittance < 0.01)
                        {
                            //截断
                            break;
                        }
                        float3 lightReceive = lightmarchEarth(currentPos, 0);

                        cloudColor += Scattering(tau, cosAngle, lightReceive, stepsize, currentDensity)
                            * stepsize;
                        //cloudColor += lightReceive * transmittance * (_sigma_s * currentDensity) * phase(cosAngle) ;
                        densityPrevious = currentDensity;
                    }
                }

                if (inCloudMarchedLength < inCloudMarchLimit)
                {
                    //show truncation with insufficient step size
                    if (_showTruncation == 1)
                        return float4(float3(1, 1, 0), Beer(tau, _sigma_t));
                }
                return float4(cloudColor, Beer(tau, _sigma_t));
            }

            v2f vert(a2v i)
            {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                o.uv = i.texcoord;

                int index = 0;
                if (i.texcoord.x < 0.5 && i.texcoord.y < 0.5)
                {
                    index = 0;
                }
                else if (i.texcoord.x > 0.5 && i.texcoord.y < 0.5)
                {
                    index = 1;
                }
                else if (i.texcoord.x > 0.5 && i.texcoord.y > 0.5)
                {
                    index = 2;
                }
                else
                {
                    index = 3;
                }

                o.interpolatedRay = _FrustumCornersRay[index];
                return o;
            }


            half4 frag(v2f i) : SV_TARGET
            {
                //half4 backgroundColor = SAMPLE_TEXTURE2D_LOD(_MainTex, sampler_MainTex, i.uv, 0);
                
                //------------重建世界坐标-------------------------------------------------
                float RawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv);
                float3 positionWS = float3(0, 0, 0);
            #if _INTERPO_ON //射线法重建世界坐标
                float linearDepth = LinearEyeDepth(RawDepth, _ZBufferParams);
                positionWS = GetCameraPositionWS() + linearDepth * normalize(i.interpolatedRay.xyz);//normalize is nesssary
            #else
                positionWS = ComputeWorldSpacePosition(i.uv, RawDepth, UNITY_MATRIX_I_VP);
            #endif
                //return float4(positionWS.rgb, 1);

                //------------每个像素进行raymarching-------------------------------------------------
                float3 camPos = GetCameraPositionWS();
                float3 viewDir = normalize(positionWS - camPos);
                float camToOpaque = length(positionWS - camPos);

                //准备数据
                float3 EarthCenter = float3(camPos.x, -EarthRadius, camPos.z);
                float2 rayHitCloudInfo = RayCloudLayerDst(EarthCenter, EarthRadius, _CloudHeightRange.x,
                                                      _CloudHeightRange.y, camPos, viewDir);
                float inCloudMarchLimit = min(camToOpaque - rayHitCloudInfo.x, rayHitCloudInfo.y);

                //开始raymarching
                float4 cloudData = cloudRayMarchingEarth(camPos, viewDir, rayHitCloudInfo.x, inCloudMarchLimit, i.uv);
                return cloudData;
            }
            ENDHLSL
        }

        pass
        {
            //结果值为：scattering + backColor.rgb * transmittance,
            //因此为 scattering * One + backColor.rgb * SrcAlpha
            Blend One SrcAlpha

            HLSLPROGRAM
            #pragma vertex vert_blend
            #pragma fragment frag_blend

            struct appdata
            {
                float4 vertex: POSITION;
                float2 texcoord: TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex: SV_POSITION;
                float2 uv: TEXCOORD0;
            };

            v2f vert_blend(appdata v)
            {
                v2f o;
                VertexPositionInputs vertexPos = GetVertexPositionInputs(v.vertex.xyz);
                o.vertex = vertexPos.positionCS;
                o.uv = v.texcoord;
                return o;
            }

            half4 frag_blend(v2f i): SV_Target
            {
                return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
            }
            ENDHLSL

        }
    }
}