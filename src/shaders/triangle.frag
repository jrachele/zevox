#version 450

out vec4 FragColor;

void main() {
    vec2 coordColor = vec2(gl_FragCoord.x / 1920.0, gl_FragCoord.y / 1080.0);
    FragColor = vec4(coordColor, 0.2, 1.0);
}