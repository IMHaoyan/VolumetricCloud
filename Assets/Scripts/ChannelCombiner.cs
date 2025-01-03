using UnityEditor;
using UnityEngine;
using System;
using System.Linq;

public class ChannelCombiner : EditorWindow
{
    private Texture2D textureA;
    private Texture2D textureB;
    private Texture2D textureC;
    private Texture2D textureD;

    private string[] channels = { "None", "R", "G", "B", "A", "1-R", "1-G", "1-B", "1-A", "Black", "White", "Grey" };
    private int[] selectedChannels = { 0, 0, 0, 0 };

    private string[] formats = { "PNG", "TGA" };
    private int selectedFormat = 0;

    private string fileName;

    [MenuItem("TATools/Channel Combiner")]
    public static void ShowWindow()
    {
        GetWindow<ChannelCombiner>("Channel Combiner");
    }

    private void OnEnable()
    {
        fileName = DateTime.Now.ToString("yyyyMMdd_HHmmss");
    }

    private void OnGUI()
    {
        GUILayout.Label("Select Textures and Channels", EditorStyles.boldLabel);

        textureA = (Texture2D)EditorGUILayout.ObjectField("Texture A", textureA, typeof(Texture2D), false);
        selectedChannels[0] = EditorGUILayout.Popup("Channel A", selectedChannels[0], textureA == null ? channels : channels.Take(9).ToArray());

        textureB = (Texture2D)EditorGUILayout.ObjectField("Texture B", textureB, typeof(Texture2D), false);
        selectedChannels[1] = EditorGUILayout.Popup("Channel B", selectedChannels[1], textureB == null ? channels : channels.Take(9).ToArray());

        textureC = (Texture2D)EditorGUILayout.ObjectField("Texture C", textureC, typeof(Texture2D), false);
        selectedChannels[2] = EditorGUILayout.Popup("Channel C", selectedChannels[2], textureC == null ? channels : channels.Take(9).ToArray());

        textureD = (Texture2D)EditorGUILayout.ObjectField("Texture D", textureD, typeof(Texture2D), false);
        selectedChannels[3] = EditorGUILayout.Popup("Channel D", selectedChannels[3], textureD == null ? channels : channels.Take(9).ToArray());

        selectedFormat = EditorGUILayout.Popup("Save Format", selectedFormat, formats);

        fileName = EditorGUILayout.TextField("File Name", fileName);

        if (GUILayout.Button("Combine"))
        {
            CombineTextures();
        }
    }

    private void CombineTextures()
    {
        int width = 256; // Default width
        int height = 256; // Default height

        // Determine the maximum width and height from the selected textures
        if (textureA != null)
        {
            width = Mathf.Max(width, textureA.width);
            height = Mathf.Max(height, textureA.height);
        }
        if (textureB != null)
        {
            width = Mathf.Max(width, textureB.width);
            height = Mathf.Max(height, textureB.height);
        }
        if (textureC != null)
        {
            width = Mathf.Max(width, textureC.width);
            height = Mathf.Max(height, textureC.height);
        }
        if (textureD != null)
        {
            width = Mathf.Max(width, textureD.width);
            height = Mathf.Max(height, textureD.height);
        }

        Texture2D resultTexture = new Texture2D(width, height, TextureFormat.RGBA32, false);

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                Color pixel = new Color(0, 0, 0, 1); // Default to black with full alpha

                pixel.r = GetChannelValue(textureA, selectedChannels[0], x, y);
                pixel.g = GetChannelValue(textureB, selectedChannels[1], x, y);
                pixel.b = GetChannelValue(textureC, selectedChannels[2], x, y);
                pixel.a = GetChannelValue(textureD, selectedChannels[3], x, y);

                resultTexture.SetPixel(x, y, pixel);
            }
        }

        resultTexture.Apply();

        byte[] bytes;
        string fileExtension;
        string savePath = Application.dataPath + "/" + fileName;

        if (formats[selectedFormat] == "PNG")
        {
            bytes = resultTexture.EncodeToPNG();
            fileExtension = ".png";
        }
        else // TGA
        {
            bytes = resultTexture.EncodeToTGA();
            fileExtension = ".tga";
        }

        System.IO.File.WriteAllBytes(savePath + fileExtension, bytes);
        AssetDatabase.Refresh();

        Debug.Log("Texture combined and saved as " + fileName + fileExtension);
    }

    private float GetChannelValue(Texture2D texture, int channel, int x, int y)
    {
        if (texture == null)
        {
            switch (channel)
            {
                case 9: return 0; // Black
                case 10: return 1; // White
                case 11: return 0.5f; // Grey
                default: return 0;
            }
        }

        // Ensure x and y are within texture bounds
        if (x >= texture.width || y >= texture.height)
        {
            return 0; // Return 0 if out of bounds
        }

        Color pixel = texture.GetPixel(x, y);

        switch (channel)
        {
            case 1: return pixel.r;
            case 2: return pixel.g;
            case 3: return pixel.b;
            case 4: return pixel.a;
            case 5: return 1 - pixel.r;
            case 6: return 1 - pixel.g;
            case 7: return 1 - pixel.b;
            case 8: return 1 - pixel.a;
            default: return 0;
        }
    }
}
