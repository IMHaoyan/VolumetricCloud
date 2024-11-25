using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AtmosphereRenderFeature : ScriptableRendererFeature
{
    class CustomRenderPass : ScriptableRenderPass
    {
        public Settings atmosphereSettings;
        RenderTexture m_transmittanceLut;
        RenderTexture m_multiScatteringLut;
        RenderTexture m_skyViewLut;
        RenderTexture m_aerialPerspectiveLut;
        ComputeShader CS;

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            CS = atmosphereSettings.CS;
            m_transmittanceLut = RenderTexture.GetTemporary(256, 64, 0, RenderTextureFormat.ARGBFloat);
            m_transmittanceLut.enableRandomWrite = true;
            m_multiScatteringLut = RenderTexture.GetTemporary(32, 32, 0, RenderTextureFormat.ARGBFloat);
            m_multiScatteringLut.enableRandomWrite = true;
            m_skyViewLut = RenderTexture.GetTemporary(256, 128, 0, RenderTextureFormat.ARGBFloat);
            m_skyViewLut.enableRandomWrite = true;
            m_aerialPerspectiveLut = RenderTexture.GetTemporary(32 * 32, 32, 0, RenderTextureFormat.ARGBFloat);
            m_aerialPerspectiveLut.enableRandomWrite = true;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            cmd.SetGlobalTexture("_TransmittanceLut", m_transmittanceLut);
            cmd.SetGlobalTexture("_MultiScatteringLut", m_multiScatteringLut);
            cmd.SetGlobalTexture("_SkyViewLut", m_skyViewLut);

            cmd.SetGlobalFloat("SeaLevel", atmosphereSettings.SeaLevel);
            cmd.SetGlobalFloat("GroundRadius", atmosphereSettings.GroundRadius);
            cmd.SetGlobalFloat("AtmosphereHeight", atmosphereSettings.AtmosphereHeight);
            cmd.SetGlobalFloat("SunLightIntensity", atmosphereSettings.SunLightIntensity);

            cmd.SetGlobalColor("SunLightColor", atmosphereSettings.SunLightColor);
            cmd.SetGlobalFloat("SunDiskAngle", atmosphereSettings.SunDiskAngle);

            cmd.SetGlobalFloat("RayleighScatteringScale", atmosphereSettings.RayleighScatteringScale);
            cmd.SetGlobalFloat("RayleighScatteringScalarHeight", atmosphereSettings.RayleighExponentialDistribution);

            cmd.SetGlobalFloat("MieScatteringScale", atmosphereSettings.MieScatteringScale);
            cmd.SetGlobalFloat("MieAnisotropy", atmosphereSettings.MieAnisotropy);
            cmd.SetGlobalFloat("MieScatteringScalarHeight", atmosphereSettings.MieExponentialDistribution);

            cmd.SetGlobalFloat("OzoneAbsorptionScale", atmosphereSettings.OzoneAbsorptionScale);
            cmd.SetGlobalFloat("OzoneLevelCenterHeight", atmosphereSettings.OzoneTentTipAltitude);
            cmd.SetGlobalFloat("OzoneLevelWidth", atmosphereSettings.OzoneTentWidth);

            cmd.SetGlobalFloat("_AerialPerspectiveDistance", atmosphereSettings.AerialPerspectiveDistance);
            cmd.SetGlobalVector("_AerialPerspectiveVoxelSize", new Vector4(32, 32, 32, 0));

            cmd.SetGlobalFloat("MultiScatteringScale", atmosphereSettings.MultiScatteringScale);
            cmd.SetGlobalTexture("_AerialPerspectiveLut", m_aerialPerspectiveLut);

            int kernal0 = CS.FindKernel("TransmittanceLutCS");
            CS.SetTexture(kernal0, "_TransmittanceLutResult", m_transmittanceLut);
            CS.Dispatch(kernal0, 32, 8, 1);//(256,64) /8

            int kernal1 = CS.FindKernel("MultiScatteringLutCS");
            CS.SetTexture(kernal1, "_TransmittanceLut", m_transmittanceLut);
            CS.SetTexture(kernal1, "_MultiScatteringLutResult", m_multiScatteringLut);
            CS.Dispatch(kernal1, 4, 4, 1); //(32,32) /8

            int kernal2 = CS.FindKernel("SkyViewLutCS");
            CS.SetTexture(kernal2, "_TransmittanceLut", m_transmittanceLut);
            CS.SetTexture(kernal2, "_MultiScatteringLut", m_multiScatteringLut);
            CS.SetTexture(kernal2, "_SkyViewLutResult", m_skyViewLut);
            CS.Dispatch(kernal2, 32, 16, 1); //(256,128) /8

            int kernal3 = CS.FindKernel("AerialPerspectiveLutCS");
            CS.SetTexture(kernal3, "_TransmittanceLut", m_transmittanceLut);
            CS.SetTexture(kernal3, "_MultiScatteringLut", m_multiScatteringLut);
            CS.SetTexture(kernal3, "_SkyViewLut", m_skyViewLut);
            CS.SetTexture(kernal3, "_AerialPerspectiveLutResult", m_aerialPerspectiveLut);
            CS.SetFloat("_AerialPerspectiveDistance", atmosphereSettings.AerialPerspectiveDistance);
            CS.SetVector("_AerialPerspectiveVoxelSize", new Vector4(32, 32, 32, 0));
            CS.Dispatch(kernal3, 32 * 4, 4, 1); //(32*32,32) /8

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);

        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            RenderTexture.ReleaseTemporary(m_transmittanceLut);
            RenderTexture.ReleaseTemporary(m_multiScatteringLut);
            RenderTexture.ReleaseTemporary(m_skyViewLut);
            RenderTexture.ReleaseTemporary(m_aerialPerspectiveLut);
        }
    }

    CustomRenderPass m_ScriptablePass;
    [System.Serializable]
    public class Settings
    {
        [Header("Luts Computation")]
        public ComputeShader CS;
        [Header("Planet")]
        public float GroundRadius = 6360000.0f;
        public float SeaLevel = -1.0f;

        [Header("Atmosphere")]
        public float MultiScatteringScale = 1;
        public float AtmosphereHeight = 60000.0f;

        [Header("Atmosphere-Rayleigh")]
        public float RayleighScatteringScale = 1.0f;
        public float RayleighExponentialDistribution = 8000.0f;
        [Header("Atmosphere-Mie")]
        public float MieScatteringScale = 1.0f;
        public float MieAnisotropy = 0.8f;
        public float MieExponentialDistribution = 1200.0f;
        [Header("Atmosphere-Ozone")]
        public float OzoneAbsorptionScale = 1.0f;
        public float OzoneTentTipAltitude = 25000.0f;
        public float OzoneTentWidth = 15000.0f;
        
        [Header("SunLight")]
        public Color SunLightColor = Color.white;
        public float SunLightIntensity = 12.0f;
        public float SunDiskAngle = 1.5f;

        [Header("AerialPerspective Params")]
        public float AerialPerspectiveDistance = 32000.0f;
    }

    public Settings settings = new Settings();

    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass();
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRendering;
        m_ScriptablePass.atmosphereSettings = settings;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }
}


