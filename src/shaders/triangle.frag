#version 450

layout(rgba32f, binding = 1) uniform image2D img_output;

out vec4 FragColor;

void main() {
    ivec2 pixelCoords = ivec2(gl_FragCoord.xy);
    vec4 color = imageLoad(img_output, pixelCoords).rgba;
    FragColor = color;
}