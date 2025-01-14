CBUFFER_START(UnityPerMaterial)
    float _MaxStepSize;
    float _g1;
    float _g2;
    float _blendG;
    float _sigma_t;
    float _albedo;
    float _densityMultiplier;

    float4 _WeatherTex_ST;
    float4 _ShapeTex_ST;

    float _BlueNoiseStrength;

    float4 _CloudHeightRange;
    float4 _stratusInfo;
    float4 _cumulusInfo;

    float3 _windDirection;
    float _windSpeed;

    float _debugShape;
    float _debugShapeFlag;

    float _showTruncation;

    float _octaves;
    float _DirectLightMultiplier;

    float _usePhase;
    float _chosePhase;
    float _embientON;
    float _DitheringON;
    float _baseShapeDetailEffect;

    float _AdaptiveMarch;
    float4 _embientColor;
CBUFFER_END


TEXTURE2D(_WeatherTex);
SAMPLER(sampler_WeatherTex);

TEXTURE3D(_ShapeTex);
SAMPLER(sampler_ShapeTex);

TEXTURE3D(_DetailShapeTex);
SAMPLER(sampler_DetailShapeTex);

TEXTURE3D(_ShapeNoise);
SAMPLER(sampler_ShapeNoise);

float HG(float a, float g)
{
    float g2 = g * g;
    return (1 - g2) / (4 * 3.14159 * pow(abs(1 + g2 - 2 * g * a), 1.5));
}

float Schlick(float a, float g)
{
    //g: eccentricity ，HG函数的偏心率
    float g2 = g * g;
    return (1 - g2) / (4 * 3.14159 * pow(1 + g * a, 2));
}

float Cornette(float a, float g)
{
    float g2 = g * g;
    return 3 * (1 - g2) * (1 + a * a) / (8 * 3.14159 * (2 + g2) * pow(1 + g2 - 2 * g * a, 1.5));
}

float phase(float a, float g)
{
    //float p = (1 - _blendG) * HG(a, _g.x) + _blendG * HG(a, _g.y);
    // for (int index = 1; index < _octaves; index++) {
    //     p = 0.2 + p * 0.7;
    // }
    //return p;
    // if (_ShapenNoiseTiling) {
    //     return 0.5 * (1 - _blendG) * HG(a, _g.x) + _blendG * HG(a, _g.y) + 1.58;
    // }
    //if (_flag == 1)
    //    return 0.5 * (1 - _blendG) * HG(a, _g.x) + _blendG * HG(a, _g.y) + _ShapenNoiseTiling;
    //return HG(a, _g2);

    float phase = 1;
    if (_usePhase != 0)
    {
        if (_chosePhase == 0)
            phase = HG(a, g);
        else if (_chosePhase == 1)
            phase = max(HG(a, g), HG(a, -g));
        else
            phase = lerp(HG(a, g), HG(a, -g), _blendG);
    }
    return phase;
    //return max((1 - _blendG) * HG(a, _g.x), HG(a, _g.y));
    //return (1 - _blendG) * HG(a, _g.x) + _blendG * HG(a, _g.y);
}

//----------------------------- Math ---------------------------------------------//

float2 RaySphereDst(float3 sphereCenter, float sphereRadius, float3 pos, float3 rayDir)
{
    float3 oc = pos - sphereCenter;
    float b = dot(rayDir, oc);
    float c = dot(oc, oc) - sphereRadius * sphereRadius;
    float t = b * b - c; //t > 0有两个交点, = 0 相切， < 0 不相交

    float delta = sqrt(max(t, 0));
    float dstToSphere = max(-b - delta, 0);
    float dstInSphere = max(-b + delta - dstToSphere, 0);
    return float2(dstToSphere, dstInSphere);
}

//射线与云层相交, x到云层的最近距离, y穿过云层的距离
float2 RayCloudLayerDst(float3 sphereCenter, float earthRadius, float heightMin, float heightMax, float3 pos,
                        float3 rayDir, bool isShape = true)
{
    float2 cloudDstMin = RaySphereDst(sphereCenter, heightMin + earthRadius, pos, rayDir);
    float2 cloudDstMax = RaySphereDst(sphereCenter, heightMax + earthRadius, pos, rayDir);
    float dstToCloudLayer = 0;
    float dstInCloudLayer = 0;
    //形状步进时计算相交
    if (isShape)
    {
        //在地表上
        if (pos.y <= heightMin)
        {
            float3 startPos = pos + rayDir * cloudDstMin.y;
            //开始位置在地平线以上时，设置距离
            if (startPos.y >= 0)
            {
                dstToCloudLayer = cloudDstMin.y;
                dstInCloudLayer = cloudDstMax.y - cloudDstMin.y;
            }
            return float2(dstToCloudLayer, dstInCloudLayer);
        }
        //在云层内
        if (pos.y > heightMin && pos.y <= heightMax)
        {
            dstToCloudLayer = 0;
            dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x : cloudDstMax.y;
            return float2(dstToCloudLayer, dstInCloudLayer);
        }
        //在云层外
        dstToCloudLayer = cloudDstMax.x;
        dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x - dstToCloudLayer : cloudDstMax.y;
    }
    else
    {
        //光照步进时，步进开始点一定在云层内
        dstToCloudLayer = 0;
        dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x : cloudDstMax.y;
    }
    return float2(dstToCloudLayer, dstInCloudLayer);
}

float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
    return new_min + (original_value - original_min) / (original_max - original_min + 0.000001) * (new_max - new_min);
}

//----------------------------- Cloud ---------------------------------------------//

float GetCloudTypeDensity(float heightFraction, float cloud_min, float cloud_max, float feather)
{
    return saturate(Remap(heightFraction, cloud_min, cloud_min + feather * 0.5, 0, 1))
        * saturate(Remap(heightFraction, cloud_max - feather, cloud_max, 1, 0));
}


float Beer(float tau, float sigma_t)
{
    return exp(-tau * sigma_t);
    float lightDensity = tau * sigma_t;
    float beersLaw = exp(-lightDensity);
    float beersModulated = max(beersLaw, 0.7 * exp(-0.25 * lightDensity));
    return beersModulated;
}

float BeerPowder(float tau, float sigma_t)
{
    return 2.0 * exp(-tau * sigma_t) * (1.0 - exp(-2.0 * tau * sigma_t));
}

//----------------------------- Optimization ---------------------------------------------//

//获取索引， 给定一个uv， 纹理宽度高度，以及要分帧的次数，返回当前uv所对应的迭代索引
int GetIndex(float2 uv, int width, int height, int iterationCount)
{
    //分帧渲染时的顺序索引
    int FrameOrder_2x2[] = {
        0, 2, 3, 1
    };
    int FrameOrder_4x4[] = {
        0, 8, 2, 10,
        12, 4, 14, 6,
        3, 11, 1, 9,
        15, 7, 13, 5
    };

    int x = floor(uv.x * width / 8) % iterationCount; //每8*8个像素为一个最小单位组
    int y = floor(uv.y * height / 8) % iterationCount;
    int index = x + y * iterationCount;

    if (iterationCount == 2)
    {
        index = FrameOrder_2x2[index];
    }
    if (iterationCount == 4)
    {
        index = FrameOrder_4x4[index];
    }
    return index;
}

// _display1 ("------------------TEST----------------------", Int) = 1
// [KeywordEnum(ON, OFF)] _TEST ("_TEST", Float) = 0

// _sig_a ("_sig_a", Range(0, 1)) = 1
// _sig_s ("_sig_s", Range(0, 1)) = 1

// [IntRange]_stepCount ("_stepCount", Range(1, 128)) = 16

// _ShapeNoise ("_ShapeNoise", 3D) = "white" { }

// [IntRange]_powdensity ("_powdensity", Range(1, 16)) = 5
// [Toggle]_showDensity ("_showDensity ", Float) = 1

// _densityMul ("_densityMul", Range(0.002, 100)) = 1
// [IntRange]_stepCount ("_stepCount", Range(1, 128)) = 16


// float sampleDensitySphere(float3 pos) {
//     float density = SAMPLE_TEXTURE3D_LOD(_ShapeNoise, sampler_ShapeNoise, pos * _ShapeNoise_ST.x, 0).r;
//     density = Remap(density, 0, 1, 0, 0.9);
//     //return 1;
//     return pow(abs(density), _powdensity) * _densityMul;
// }


// float3 sphereCenter = _position;
// float2 rayHitInfo = RaySphereDst(sphereCenter, _radius, camPos, viewDir);
// float dstToSphere = rayHitInfo.x, dstInSphere = rayHitInfo.y;

// //begin march
// Light mainLight = GetMainLight();
// float3 lightDir = normalize(mainLight.direction);

// float cos = dot(viewDir, lightDir);
// float tau = 0;
// float transmittance = 1;

// float3 startPos = dstToSphere * viewDir + camPos;
// float stepSize = dstInSphere / _stepCount;
// half3 col = half3(0, 0, 0);
// float3 curPos = startPos;
// for (int index = 0; index < _stepCount; index++) {

//     curPos += stepSize * viewDir;
//     float density = sampleDensitySphere(curPos);
//     //debug
//     if (_showDensity && dstInSphere > 0)
//         return half4(half3(1, 1, 1) * density, 1);

//     if (density < 0.001)
//         continue;

//     transmittance *= exp(-stepSize * density * (_sig_a + _sig_s));

//     if (transmittance < 0.01) {
//         //截断
//         break;
//     }

//     //march the light
//     float2 rayHitInfo_light = RaySphereDst(sphereCenter, _radius, curPos, lightDir);
//     float stepSize_light = rayHitInfo_light.y / 8.0;

//     float tau_light = 0;
//     float3 position = curPos;
//     for (int step = 0; step < 8; step++) {
//         position += lightDir * stepSize_light; //向灯光步进
//         tau_light += stepSize_light * sampleDensitySphere(position); //步进的时候采样噪音累计受灯光影响密度

//     }
//     float light_attenuation = Beer(tau_light, (_sig_a + _sig_s));
//     float3 Li = mainLight.color * light_attenuation;
//     //Li = half3(1, 1, 1);

//     col += Li * phase(cos, _g2) * transmittance * (_sig_s * density) * stepSize;
// }
// return half4(col / (1 - transmittance), 1 - transmittance);
