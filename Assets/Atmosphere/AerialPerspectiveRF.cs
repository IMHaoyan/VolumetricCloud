using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AerialPerspectiveRF : ScriptableRendererFeature
{
    class AerialPerspectivePass : ScriptableRenderPass
    {
        public Material passMat = null;
        RenderTargetIdentifier passSource { get; set; }
        int tempID = Shader.PropertyToID("_tempRT");

        public AerialPerspectivePass(Setting mySetting)
        {
            passMat = mySetting.AerialPerspecMat;
        }
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            passSource = renderingData.cameraData.renderer.cameraColorTargetHandle;

            RenderTextureDescriptor CameraTexDesc = renderingData.cameraData.cameraTargetDescriptor;
            CameraTexDesc.depthBufferBits = 0;
            cmd.GetTemporaryRT(tempID, CameraTexDesc);
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("AerialPerspectivePass");
            cmd.Blit(passSource, tempID, passMat);
            cmd.Blit(tempID, passSource);

            context.ExecuteCommandBuffer(cmd);//执行命令
            cmd.ReleaseTemporaryRT(tempID);
            cmd.Clear();
            cmd.Release();
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    [System.Serializable]
    public class Setting
    {
        public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public Material AerialPerspecMat;
    }

    public Setting mySetting = new Setting();
    AerialPerspectivePass myPass;

    public override void Create()
    {
        myPass = new AerialPerspectivePass(mySetting);
        myPass.renderPassEvent = mySetting.passEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (mySetting.AerialPerspecMat == null)
        {
            Debug.LogError("材质球丢失！请设置材质球");
        }
        renderer.EnqueuePass(myPass);
    }
}


