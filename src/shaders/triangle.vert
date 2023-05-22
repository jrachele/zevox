#version 450

layout (location = 0) in vec3 aPos;

layout (std140) uniform RotationBlock {
    uniform vec2 rotation;
};

void main() {
    gl_Position = vec4(aPos.x + rotation.x, aPos.y + rotation.y, aPos.z, 1.0);
}