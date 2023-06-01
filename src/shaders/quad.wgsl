@vertex fn vert_main(
    @builtin(vertex_index) VertexIndex : u32
) -> @builtin(position) vec4<f32> {
    var pos = array<vec2<f32>, 6>(
      vec2<f32>(-1.0, -1.0),
      vec2<f32>(1.0, -1.0),
      vec2<f32>(-1.0, 1.0),
      vec2<f32>(1.0, -1.0),
      vec2<f32>(-1.0, 1.0),
      vec2<f32>(1.0, 1.0)
    );
    return vec4<f32>(pos[VertexIndex], 0.0, 1.0);
}

@group(0) @binding(0) 
var output_texture: texture_2d<f32>;

@fragment fn frag_main(@builtin(position) FragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    var color = textureLoad(output_texture, vec2<i32>(FragCoord.xy), 0);
    return color;
}
