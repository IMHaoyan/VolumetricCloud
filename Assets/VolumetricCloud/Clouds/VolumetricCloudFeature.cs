using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumetricCloudFeature : ScriptableRendererFeature
{
    public enum FrameBlock
    {
        _Off = 1,
        _2x2 = 4,
        _4x4 = 16
    }

    [System.Serializable]
    public class Setting
    {
        [Header("Luts Computation")] public float4 cloudLayer1;
        public float4 cloudLayer2;
        public float4 cloudLayer3;

        public ComputeShader CS;

        //后处理进行体积云云渲染的材质
        public Material CloudMaterial;

        //体积云渲染的插入阶段
        public RenderPassEvent PassEvent = RenderPassEvent.AfterRenderingTransparents; //半透明物体应该遮挡云

        public Texture2D BlueNoiseTex;

        //体积云渲染目标比例
        [Range(0.1f, 1)] public float RTScale = 0.5f;

        //分帧渲染
        public FrameBlock FrameBlocking = FrameBlock._Off;

        //屏蔽相机分辨率宽度(受纹理缩放影响)
        [Range(100, 600)] public int ShieldWidth = 400;

        //是否开启分帧测试
        public bool IsFrameDebug = false;

        //分帧测试
        [Range(1, 16)] public int FrameDebug = 1;
    }

    class VolumetricCloudPass : ScriptableRenderPass
    {
        public Setting Set;
        RenderTexture verticalProfileLut;
        public string cmdName;

        public RenderTargetIdentifier cameraColorTex;

        //云渲染纹理， 通过两张进行相互迭代，完成分帧渲染
        public RenderTexture[] cloudTex;


        //云纹理的宽度
        public int width;

        //云纹理的高度
        public int height;

        //帧计数
        public int frameCount;

        //纹理切换
        public int rtSwitch;

        Matrix4x4 frustumCorners;

        ProfilingSampler passProfilingSampler = new ProfilingSampler("VolumetricCloudFeatureProfiling");

        public VolumetricCloudPass(Setting set, string name)
        {
            Set = set;
            this.cmdName = name;
            this.frameCount = 0;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            cameraColorTex = renderingData.cameraData.renderer.cameraColorTargetHandle;

            RenderTextureDescriptor desc = new RenderTextureDescriptor(64, 64, RenderTextureFormat.ARGB32, 0);
            desc.enableRandomWrite = true; // 允许随机写入
            verticalProfileLut = RenderTexture.GetTemporary(desc);


            // verticalProfileLut = RenderTexture.GetTemporary(64, 64, 0, RenderTextureFormat.ARGB32);
            // verticalProfileLut.enableRandomWrite = true;

            //Debug.Log(verticalProfileLut.sRGB);
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
                Set.CloudMaterial.SetMatrix("_CurrentViewProjectionInverseMatrix", currentViewProjectionInverseMatrix);

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
                Set.CloudMaterial.SetMatrix("_FrustumCornersRay", frustumCorners);

            #endregion

                //CS
                cmd.SetGlobalTexture("_VerticalProfileLut", verticalProfileLut);
                int cloudKernal = Set.CS.FindKernel("CloudCS");
                Set.CS.SetTexture(cloudKernal, "_Result", verticalProfileLut);
                cmd.SetGlobalVector("_cloudLayer1", Set.cloudLayer1);
                cmd.SetGlobalVector("_cloudLayer2", Set.cloudLayer2);
                cmd.SetGlobalVector("_cloudLayer3", Set.cloudLayer3);
                Set.CS.SetVector("_cloudLayer1", Set.cloudLayer1);
                Set.CS.SetVector("_cloudLayer2", Set.cloudLayer2);
                Set.CS.SetVector("_cloudLayer3", Set.cloudLayer3);
                Set.CS.Dispatch(cloudKernal, 8, 8, 1); //(64,64) /8

                Set.CloudMaterial.SetInt("_Width", width - 1);
                Set.CloudMaterial.SetInt("_Height", height - 1);
                Set.CloudMaterial.SetTexture("_BlueNoiseTex", Set.BlueNoiseTex);
                Set.CloudMaterial.SetVector("_BlueNoiseTexUV",
                    new Vector4((float)width / (float)Set.BlueNoiseTex.width,
                        (float)height / (float)Set.BlueNoiseTex.height, 0, 0));

                Set.CloudMaterial.SetInt("_FrameCount", frameCount);
                //如果不开启分帧渲染
                if (Set.FrameBlocking == FrameBlock._Off)
                {
                    Set.CloudMaterial.EnableKeyword("_OFF");
                    Set.CloudMaterial.DisableKeyword("_2X2");
                    Set.CloudMaterial.DisableKeyword("_4X4");
                }
                else if (Set.FrameBlocking == FrameBlock._2x2)
                {
                    Set.CloudMaterial.DisableKeyword("_OFF");
                    Set.CloudMaterial.EnableKeyword("_2X2");
                    Set.CloudMaterial.DisableKeyword("_4X4");
                }
                else if (Set.FrameBlocking == FrameBlock._4x4)
                {
                    Set.CloudMaterial.DisableKeyword("_OFF");
                    Set.CloudMaterial.DisableKeyword("_2X2");
                    Set.CloudMaterial.EnableKeyword("_4X4");
                }

                //如果不开启分帧渲染，我们将创建临时渲染纹理
                if (Set.FrameBlocking == FrameBlock._Off)
                {
                    //RenderCloud
                    int temTextureID = Shader.PropertyToID("_CloudTex");
                    cmd.GetTemporaryRT(temTextureID, width, height, 0, FilterMode.Point,
                        format: RenderTextureFormat.ARGB32);

                    cmd.Blit(cameraColorTex, temTextureID, Set.CloudMaterial, 0);
                    cmd.Blit(temTextureID, cameraColorTex, Set.CloudMaterial, 1);

                    //释放资源
                    cmd.ReleaseTemporaryRT(temTextureID);
                }
                else
                {
                    cmd.Blit(cloudTex[rtSwitch % 2], cloudTex[(rtSwitch + 1) % 2], Set.CloudMaterial, 0);
                    cmd.Blit(cloudTex[(rtSwitch + 1) % 2], cameraColorTex, Set.CloudMaterial, 1);
                }
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd); //释放回收 
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    VolumetricCloudPass volumetricCloudPass;
    public Setting Set;

    //云渲染纹理， 通过两张进行相互迭代，完成分帧渲染
    private RenderTexture[] _cloudTex_game = new RenderTexture[2];

    //预览窗口和游戏视口需要分开
    private RenderTexture[] _cloudTex_sceneView = new RenderTexture[2];

    //上一次纹理分辨率
    private int _width_game, _height_game;
    private int _width_sceneView, _height_sceneView;

    //当前帧数
    private int _frameCount_game;
    private int _frameCount_sceneView;

    //纹理切换
    private int _rtSwitch_game;
    private int _rtSwitch_sceneView;

    //上一次分帧测试数值
    private int _frameDebug = 1;

    public override void Create()
    {
        volumetricCloudPass = new VolumetricCloudPass(Set, this.name); //实例化一下并传参数,name就是tag
        volumetricCloudPass.renderPassEvent = Set.PassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!Set.CloudMaterial || !Set.BlueNoiseTex)
        {
            Debug.LogError("体积云材质球或白噪声纹理丢失！请在Renderfeature内设置");
            return;
        }

        if (!(renderingData.cameraData.cameraType == CameraType.Game ||
              renderingData.cameraData.cameraType == CameraType.SceneView))
        {
            return;
        }

        //云纹理目标渲染分辨率
        int width = (int)(renderingData.cameraData.cameraTargetDescriptor.width * Set.RTScale);
        int height = (int)(renderingData.cameraData.cameraTargetDescriptor.height * Set.RTScale);

        if (Set.FrameBlocking == FrameBlock._Off) //不进行分帧渲染
        {
            for (int i = 0; i < 2; i++)
            {
                //重置纹理
                RenderTexture.ReleaseTemporary(_cloudTex_game[i]);
                RenderTexture.ReleaseTemporary(_cloudTex_sceneView[i]);
            }

            _cloudTex_game = new RenderTexture[2];
            _cloudTex_sceneView = new RenderTexture[2];

            volumetricCloudPass.width = width;
            volumetricCloudPass.height = height;
        }
        else //进行分帧渲染
        {
            //分帧调试
            if (Set.IsFrameDebug)
            {
                if (Set.FrameDebug != _frameDebug)
                {
                    for (int i = 0; i < 2; i++)
                    {
                        //重置纹理
                        RenderTexture.ReleaseTemporary(_cloudTex_game[i]);
                        RenderTexture.ReleaseTemporary(_cloudTex_sceneView[i]);
                    }

                    _cloudTex_game = new RenderTexture[2];
                    _cloudTex_sceneView = new RenderTexture[2];
                }

                _frameDebug = Set.FrameDebug;
                //分帧测试
                _frameCount_game = _frameCount_game % Set.FrameDebug;
                _frameCount_sceneView = _frameCount_sceneView % Set.FrameDebug;
            }

            //对Game视口和Scene视口进行分别处理，内容基本一致s
            if (renderingData.cameraData.cameraType == CameraType.Game)
            {
                //创建纹理
                for (int i = 0; i < 2; i++)
                {
                    if (_cloudTex_game[i] != null && _width_game == width && _height_game == height)
                        continue;
                    //当选中相机时，右下角会有一个预览窗口，他的分辨率与当前game视口不一样，所以会进行打架
                    //在这设置阈值，屏蔽掉预览窗口的变化
                    if (width < Set.ShieldWidth)
                        continue;

                    //创建Game视口的渲染纹理
                    _cloudTex_game[i] = RenderTexture.GetTemporary(width, height, 0, RenderTextureFormat.ARGB32);

                    _width_game = width;
                    _height_game = height;
                }

                volumetricCloudPass.cloudTex = _cloudTex_game;
                volumetricCloudPass.width = _width_game;
                volumetricCloudPass.height = _height_game;
                volumetricCloudPass.frameCount = _frameCount_game;
                volumetricCloudPass.rtSwitch = _rtSwitch_game;

                _rtSwitch_game = (++_rtSwitch_game) % 2;
                //增加帧数
                _frameCount_game = (++_frameCount_game) % (int)Set.FrameBlocking;
            }
            else
            {
                //创建纹理
                for (int i = 0; i < _cloudTex_sceneView.Length; i++)
                {
                    if (_cloudTex_sceneView[i] != null && _width_sceneView == width && _height_sceneView == height)
                        continue;

                    //创建场景视口的渲染纹理
                    _cloudTex_sceneView[i] = RenderTexture.GetTemporary(width, height, 0, RenderTextureFormat.ARGB32);

                    _width_sceneView = width;
                    _height_sceneView = height;
                }

                volumetricCloudPass.cloudTex = _cloudTex_sceneView;
                volumetricCloudPass.width = _width_sceneView;
                volumetricCloudPass.height = _height_sceneView;
                volumetricCloudPass.frameCount = _frameCount_sceneView;
                volumetricCloudPass.rtSwitch = _rtSwitch_sceneView;

                _rtSwitch_sceneView = (++_rtSwitch_sceneView) % 2;
                //增加帧数
                _frameCount_sceneView = (++_frameCount_sceneView) % (int)Set.FrameBlocking;
            }
        }

        renderer.EnqueuePass(volumetricCloudPass);
    }
}