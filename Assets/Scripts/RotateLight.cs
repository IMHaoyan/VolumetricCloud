using UnityEngine;
public class RotateLight : MonoBehaviour
{
    public float speed = 10.0f;
    void Update()
    {
        if (Input.GetKey(KeyCode.C))
        {
            transform.Rotate(Vector3.right, -speed * Time.deltaTime);
        }
        if (Input.GetKey(KeyCode.Z))
        {
            transform.Rotate(Vector3.right, speed * Time.deltaTime);
        }
    }
}
