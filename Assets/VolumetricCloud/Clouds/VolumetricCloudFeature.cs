using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumetricCloudFeature : ScriptableRendererFeature
{
    class VolumetricCloudPass : ScriptableRenderPass
    {
        public Material passMat;
        public string cmdName;
        RenderTargetIdentifier passSource;
        int passTempTexID = Shader.PropertyToID("_CloudTex");

        //云纹理的宽度
        public int width;

        //云纹理的高度
        public int height;

        Matrix4x4 frustumCorners;

        ProfilingSampler passProfilingSampler = new ProfilingSampler("VolumetricCloudFeatureProfiling");

        public VolumetricCloudPass(Setting setting, string name)
        {
            passMat = setting.cloudMaterial;
            cmdName = name;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(cmdName);
            using (new ProfilingScope(cmd, passProfilingSampler))
            {
            #region 射线法重建世界坐标

                Camera camera = renderingData.cameraData.camera;
                Matrix4x4 currentViewProjectionMatrix = camera.projectionMatrix * camera.worldToCameraMatrix;
                Matrix4x4 currentViewProjectionInverseMatrix = currentViewProjectionMatrix.inverse;
                passMat.SetMatrix("_CurrentViewProjectionInverseMatrix", currentViewProjectionInverseMatrix);

                Transform cameraTransform = camera.transform;
                float fov = camera.fieldOfView;
                float near = camera.nearClipPlane;
                float far = camera.farClipPlane;
                float aspect = camera.aspect;

                float halfHeight = near * Mathf.Tan(fov * 0.5f * Mathf.Deg2Rad);
                Vector3 toRight = cameraTransform.right * halfHeight * aspect;
                Vector3 toTop = cameraTransform.up * halfHeight;
                Vector3 topLeft = cameraTransform.forward * near + toTop - toRight;
                float scale = topLeft.magnitude / near;
                topLeft.Normalize();
                topLeft *= scale;
                Vector3 topRight = cameraTransform.forward * near + toRight + toTop;
                topRight.Normalize();
                topRight *= scale;
                Vector3 bottomLeft = cameraTransform.forward * near - toTop - toRight;
                bottomLeft.Normalize();
                bottomLeft *= scale;
                Vector3 bottomRight = cameraTransform.forward * near + toRight - toTop;
                bottomRight.Normalize();
                bottomRight *= scale;

                frustumCorners.SetRow(0, bottomLeft);
                frustumCorners.SetRow(1, bottomRight);
                frustumCorners.SetRow(2, topRight);
                frustumCorners.SetRow(3, topLeft);
                passMat.SetMatrix("_FrustumCornersRay", frustumCorners);
                passMat.SetFloat("_ZFar", camera.farClipPlane);

            #endregion
                RenderCloud(cmd, renderingData);
            }

            context.ExecuteCommandBuffer(cmd); //执行命令
            CommandBufferPool.Release(cmd); //释放回收 
        }

        void RenderCloud(CommandBuffer cmd, RenderingData renderingData)
        {
            cmd.GetTemporaryRT(passTempTexID, width, height, 0,
                filter: FilterMode.Bilinear);

            passSource = renderingData.cameraData.renderer.cameraColorTargetHandle;
            cmd.Blit(passSource, passTempTexID, passMat, 0);
            cmd.Blit(passTempTexID, passSource, passMat, 1);
        }
        
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(passTempTexID);
        }
    }

    public enum FrameBlock
    {
        _Off = 1,
        _2x2 = 4,
        _4x4 = 16
    }

    [System.Serializable]
    public class Setting
    {
        public Material cloudMaterial;

        public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingTransparents;

        //分辨率缩放
        [Range(0.1f, 1)] public float rtScale = 0.5f;

        //分帧渲染
        public FrameBlock frameBlocking = FrameBlock._4x4;

        //屏蔽相机分辨率宽度(受纹理缩放影响)
        [Range(100, 600)] public int shieldWidth = 400;

        //是否开启分帧测试
        public bool isFrameDebug = false;

        //分帧测试
        [Range(1, 16)] public int frameDebug = 1;
    }

    public Setting setting;
    VolumetricCloudPass volumetricCloudPass;

    public override void Create()
    {
        volumetricCloudPass = new VolumetricCloudPass(setting, this.name); //实例化一下并传参数,name就是tag
        volumetricCloudPass.renderPassEvent = setting.passEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!setting.cloudMaterial)
        {
            Debug.LogError("材质球丢失！请设置材质球");
            return;
        }

        if (!(renderingData.cameraData.cameraType == CameraType.Game ||
              renderingData.cameraData.cameraType == CameraType.SceneView))
        {
            return;
        }

        //云纹理分辨率
        int width = (int)(renderingData.cameraData.cameraTargetDescriptor.width * setting.rtScale);
        int height = (int)(renderingData.cameraData.cameraTargetDescriptor.height * setting.rtScale);

        //不进行分帧渲染
        if (true || setting.frameBlocking == FrameBlock._Off)
        {
            // for (int i = 0; i < 2; i++)
            // {
            //     //重置纹理
            //     RenderTexture.ReleaseTemporary(_cloudTex_game[i]);
            //     RenderTexture.ReleaseTemporary(_cloudTex_sceneView[i]);
            //     _cloudTex_game = new RenderTexture[2];
            //     _cloudTex_sceneView = new RenderTexture[2];
            // }

            volumetricCloudPass.width = width;
            volumetricCloudPass.height = height;
            //volumetricCloudPass.cameraColorTex = renderer.cameraColorTarget;
            renderer.EnqueuePass(volumetricCloudPass);
            return;
        }
    }
}