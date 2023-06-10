@group(0) @binding(0)
var<storage, read> voxels: array<u32>;

@group(0) @binding(1)
var output_texture: texture_storage_2d<rgba8unorm, write>;

struct RaytracingData {
    dim: u32,
    pos: vec3<f32>,
    camera_matrix: mat4x4<f32>,
    inverse_projection_matrix: mat4x4<f32>,
};

@group(0) @binding(2)
var<uniform> raytracing_data: RaytracingData;

const VOXEL_SIZE: f32 = 1.0;
const EMPTY_VOXEL: u32 = 0u;

fn get_index(index: vec3<i32>) -> u32 {
    let dim = i32(raytracing_data.dim);
    return u32((index.x * dim * dim) + (index.y * dim) + index.z);
}

fn out_of_bounds(index: vec3<i32>) -> bool {
    let dim = i32(raytracing_data.dim);
    return index.x < 0 || index.x >= dim || index.y < 0 || index.y >= dim || index.z < 0 || index.z >= dim;
}

fn ray_grid_intersection(ray_origin: vec3<f32>, ray_direction: vec3<f32>, grid_position: vec3<f32>, grid_size: vec3<f32>) -> vec3<f32> {
    let t_min: vec3<f32> = (grid_position - ray_origin) / ray_direction;
    let t_max: vec3<f32> = (grid_position + grid_size - ray_origin) / ray_direction;

    let t_enter: f32 = max(max(min(t_min.x, t_max.x), min(t_min.y, t_max.y)), min(t_min.z, t_max.z));
    let t_exit: f32 = min(min(max(t_min.x, t_max.x), max(t_min.y, t_max.y)), max(t_min.z, t_max.z));

    if t_enter > t_exit || t_exit < 0.0 {
        // No intersection with the grid
        return vec3<f32>(-100.0);
    }

    return ray_origin + ray_direction * t_enter;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) invocation_id: vec3<u32>) {
    let dim = f32(raytracing_data.dim);
    let grid_pos = raytracing_data.pos;
    let pixel_coords = invocation_id.xy;

    let camera_matrix = raytracing_data.camera_matrix;
    let inverse_projection_matrix = raytracing_data.inverse_projection_matrix;

    let screen_size = vec2<f32>(textureDimensions(output_texture));
    let ndc_space = ((vec2<f32>(f32(pixel_coords.x), screen_size.y - f32(pixel_coords.y)) / screen_size) * 2.0) - vec2<f32>(1.0);

    let ray_start = camera_matrix * inverse_projection_matrix * vec4<f32>(ndc_space, 0.0, 1.0);
    let ray_end = camera_matrix * inverse_projection_matrix * vec4<f32>(ndc_space, 1.0, 1.0);
    let ray_direction = normalize((ray_end.xyz / ray_end.w) - (ray_start.xyz / ray_start.w));

    let grid_size = vec3<f32>(dim);
    let boundary_bottom_left = vec3<i32>(grid_pos);
    let boundary_top_right = vec3<i32>(grid_pos + (grid_size * VOXEL_SIZE));

    var voxel_position = vec3<i32>(ray_start.xyz);
    if voxel_position.x < boundary_bottom_left.x || voxel_position.y < boundary_bottom_left.y || voxel_position.z < boundary_bottom_left.z || voxel_position.x >= boundary_top_right.x || voxel_position.y >= boundary_top_right.y || voxel_position.z >= boundary_top_right.z {
        voxel_position = vec3<i32>(ray_grid_intersection(ray_start.xyz, ray_direction, grid_pos, grid_size));
    }

    let delta_dist = abs(1.0 / (ray_direction * VOXEL_SIZE));
    let step = vec3<i32>(sign(ray_direction) * VOXEL_SIZE);
    var side_dist = (sign(ray_direction) * (vec3<f32>(voxel_position) - ray_start.xyz) + (sign(ray_direction) * 0.5) + 0.5) * delta_dist;

    var color = vec4<f32>(0.0);
    // let maxSteps = u32(dim * 1.41);
    let maxSteps = u32(256 * 1.41);
    var mask = vec3<bool>(false);

    let x = voxels[0];

    for (var i = 0u; i < maxSteps; i++) {
        let index = vec3<f32>(voxel_position);
        var voxel = EMPTY_VOXEL;

        let index_i = vec3<i32>(index);
        let dim_i = i32(dim);
        if index_i.x < 0 || index_i.x >= dim_i || index_i.y < 0 || index_i.y >= dim_i || index_i.z < 0 || index_i.z >= dim_i {
            break;
        }

        voxel = voxels[get_index(vec3<i32>(index))];

        if voxel != EMPTY_VOXEL {
            color = vec4<f32>(vec2<f32>(invocation_id.xy) / screen_size, 0.8, 0.0);
            break;
        }

        // Branchless DDA
        mask = side_dist.xyz <= min(side_dist.yzx, side_dist.zxy);
        side_dist += vec3<f32>(mask) * delta_dist;
        voxel_position += vec3<i32>(vec3<f32>(mask)) * step;

        // Normal DDA
        // if side_dist.x < side_dist.y {
        //     if side_dist.x < side_dist.z {
        //         side_dist.x += delta_dist.x;
        //         voxel_position.x += step.x;
        //         mask = vec3<bool>(true, false, false);
        //     } else {
        //         side_dist.z += delta_dist.z;
        //         voxel_position.z += step.z;
        //         mask = vec3<bool>(false, false, true);
        //     }
        // } else {
        //     if side_dist.y < side_dist.z {
        //         side_dist.y += delta_dist.y;
        //         voxel_position.y += step.y;
        //         mask = vec3<bool>(false, true, false);
        //     } else {
        //         side_dist.z += delta_dist.z;
        //         voxel_position.z += step.z;
        //         mask = vec3<bool>(false, false, true);
        //     }
        // }
    }

    if mask.y {
        color *= 0.9;
    }
    if mask.z {
        color *= 0.75;
    }

    textureStore(output_texture, invocation_id.xy, color);
}

