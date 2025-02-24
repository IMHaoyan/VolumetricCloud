using UnityEngine;
using System.Collections.Generic;
using System.IO;

public class FPSLogger : MonoBehaviour
{
    [Range(0.05f,10.0f)]public float updateInterval = 0.1f; // 每隔1秒记录一次帧率
    private float timeElapsed = 0f;
    private int frameCount = 0;
    private List<float> fpsLog = new List<float>(); // 存储帧率数据
    private List<float> timeLog = new List<float>(); // 存储时间戳

    void Update()
    {
        // 计算实时帧率
        timeElapsed += Time.unscaledDeltaTime;
        frameCount++;

        if (timeElapsed >= updateInterval)
        {
            float fps = frameCount / timeElapsed;
            fpsLog.Add(fps); // 记录帧率
            timeLog.Add(Time.time); // 记录时间戳

            // 重置计数器
            frameCount = 0;
            timeElapsed = 0f;
            if (Time.time >= 80)
            {
                SaveToCSV();
                UnityEditor.EditorApplication.isPlaying = false;
            }
            // 显示当前帧率（可选）
            Debug.Log($"FPS: {fps:F2} at Time: {Time.time:F2}");
        }

        // 按下特定键（例如 "S"）保存数据
        if (Input.GetKeyDown(KeyCode.S))
        {
            SaveToCSV();
            UnityEditor.EditorApplication.isPlaying = false;

        }
    }

    void SaveToCSV()
    {
        // 设置保存路径（桌面）
        
        var currentTime = System.DateTime.Now;
        var filename = "FPSLog-"+currentTime.ToString().Replace('/', '-').Replace(':', '_') + ".csv";
        string filePath = Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.Desktop), filename);

        // 创建 CSV 文件内容
        using (StreamWriter writer = new StreamWriter(filePath))
        {
            writer.WriteLine("Time,FPS"); // 写入表头
            for (int i = 0; i < fpsLog.Count; i++)
            {
                writer.WriteLine($"{timeLog[i]:F2},{fpsLog[i]:F2}"); // 写入时间和帧率
            }
        }

        Debug.Log($"FPS data saved to: {filePath}");
    }

    // 可选：程序退出时自动保存
    void OnApplicationQuit()
    {
        //SaveToCSV();
    }
}