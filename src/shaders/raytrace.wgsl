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
    return index.x < 0 || index.x >= dim ||
        index.y < 0 || index.y >= dim ||
        index.z < 0 || index.z >= dim;
}

// This may become useful sometime
fn out_of_invocation_bounds(invocation_id: vec3<u32>, invocation_id_local: vec3<u32>, index: vec3<i32>) -> bool {
    let boundary_bottom_left = vec3<i32>(invocation_id - invocation_id_local);
    let boundary_top_right = boundary_bottom_left + vec3<i32>(8, 8, 8);
    return index.x < boundary_bottom_left.x || index.y < boundary_bottom_left.y || index.z < boundary_bottom_left.z ||
        index.x >= boundary_top_right.x || index.y >= boundary_top_right.y || index.z >= boundary_top_right.z;
}

fn get_voxel_color(voxel_data: u32) -> vec3<f32> {
    let mask_5 = 31u;
    let mask_6 = 63u;
    let r_offset = 32u - 5u;
    let g_offset = 32u - 11u;
    let b_offset = 32u - 16u;
    let r: u32 = (voxel_data & (mask_5 << r_offset)) >> r_offset;
    let g: u32 = (voxel_data & (mask_6 << g_offset)) >> g_offset;
    let b: u32 = (voxel_data & (mask_5 << b_offset)) >> b_offset;
    return vec3<f32>(f32(r) / f32(mask_5), f32(g) / f32(mask_6), f32(b) / f32(mask_5));
}

fn set_voxel_color(voxel_data: u32, color: vec3<f32>) -> u32 {
    let r: u32 = u32(color.x * 31.0);
    let g: u32 = u32(color.y * 63.0);
    let b: u32 = u32(color.z * 31.0);
    let r_offset = 32u - 5u;
    let g_offset = 32u - 11u;
    let b_offset = 32u - 16u;
    var voxel = voxel_data;
    voxel |= (r << r_offset);
    voxel |= (g << g_offset);
    voxel |= (b << b_offset);
    return voxel;
}

fn get_voxel_type(voxel_data: u32) -> u32 {
    return voxel_data & 255u;
}

fn set_voxel_type(voxel_data: u32, voxel_type: u32) -> u32 {
    var voxel = voxel_data;
    voxel >>= 8u;
    voxel <<= 8u;
    voxel |= voxel_type & 255u;
    return voxel;

}

fn ray_grid_intersection(ray_origin: vec3<f32>, ray_direction: vec3<f32>, grid_position: vec3<f32>, grid_size: vec3<f32>) -> vec3<f32> {
    let t_min: vec3<f32> = (grid_position - ray_origin) / ray_direction;
    let t_max: vec3<f32> = (grid_position + grid_size - ray_origin) / ray_direction;

    let t_enter: f32 = max(max(min(t_min.x, t_max.x), min(t_min.y, t_max.y)), min(t_min.z, t_max.z));
    let t_exit: f32 = min(min(max(t_min.x, t_max.x), max(t_min.y, t_max.y)), max(t_min.z, t_max.z));

    if (t_enter > t_exit || t_exit < 0.0) {
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
    if (voxel_position.x < boundary_bottom_left.x || voxel_position.y < boundary_bottom_left.y || voxel_position.z < boundary_bottom_left.z ||
        voxel_position.x >= boundary_top_right.x || voxel_position.y >= boundary_top_right.y || voxel_position.z >= boundary_top_right.z) {
        voxel_position = vec3<i32>(ray_grid_intersection(ray_start.xyz, ray_direction, grid_pos, grid_size));
    }


    let delta_dist = abs(1.0 / (ray_direction * VOXEL_SIZE));
    let step = vec3<i32>(sign(ray_direction) * VOXEL_SIZE);
    var side_dist = (sign(ray_direction) * (vec3<f32>(voxel_position) - ray_start.xyz) + (sign(ray_direction) * 0.5) + 0.5) * delta_dist;

    var color = vec4<f32>(0.0);
    let maxSteps = u32(dim * 2.0);
    var mask = vec3<bool>(false);
    let center_pixel = ndc_space.x == 0.0 && ndc_space.y == 0.0;
    let x = voxels[0];

    


    for (var i = 0u; i < maxSteps; i++) {
        if (voxel_position.x < boundary_bottom_left.x || voxel_position.x > boundary_top_right.x ||
            voxel_position.y < boundary_bottom_left.y || voxel_position.y > boundary_top_right.y ||
            voxel_position.z < boundary_bottom_left.z || voxel_position.z > boundary_top_right.z) {
            break;
        }

        // let index = vec3<f32>(vec3<f32>((voxel_position-vec3<i32>(grid_pos))) / VOXEL_SIZE);
        let index = vec3<f32>(voxel_position);
        var voxel = voxels[get_index(vec3<i32>(index))];
        if (out_of_bounds(vec3<i32>(index))) {
            voxel = EMPTY_VOXEL;
            // break;
        }
        if (voxel != EMPTY_VOXEL) {
            //color = vec4<f32>(get_voxel_color(voxel), 1.0);
            color = vec4<f32>(vec2<f32>(invocation_id.xy) / screen_size ,0.8, 0.0);
            // if (get_voxel_type(voxel) == 1u) {
            //     color.w = 0.1;
            // }

            // let center_voxel_already_selected = raytracing_data.selected.x == index.x && raytracing_data.selected.y == index.y && raytracing_data.selected.z == index.z;
            // if (center_pixel) {
            //     raytracing_data.selected = index;
            // }

            // // TODO: Render brush as sphere with radius, in separate function
            // if (center_voxel_already_selected) {
            //     color = vec4<f32>(1.0, 1.0, 1.0, 1.0);
            // }
            break;
        }

        if (side_dist.x < side_dist.y) {
            if (side_dist.x < side_dist.z) {
                side_dist.x += delta_dist.x;
                voxel_position.x += step.x;
                mask = vec3<bool>(true, false, false);
            } else {
                side_dist.z += delta_dist.z;
                voxel_position.z += step.z;
                mask = vec3<bool>(false, false, true);
            }
        } else {
            if (side_dist.y < side_dist.z) {
                side_dist.y += delta_dist.y;
                voxel_position.y += step.y;
                mask = vec3<bool>(false, true, false);
            } else {
                side_dist.z += delta_dist.z;
                voxel_position.z += step.z;
                mask = vec3<bool>(false, false, true);
            }
        }

    }
    if (mask.y) {
        color *= 0.9;
    }
    if (mask.z) {
        color *= 0.75;
    }

    // if (color.x != 0.0 || color.y != 0.0 || color.z != 0.0) {
    //     color.w = 1.0;
    // }

    // if (center_pixel) {
    //     raytracing_data.normal = vec3<f32>(0.0);
    //     if (mask.x) {
    //         raytracing_data.normal.x = -sign(ray_direction.x);
    //     }
    //     else if (mask.y) {
    //         raytracing_data.normal.y = -sign(ray_direction.y);
    //     }
    //     else if (mask.z) {
    //         raytracing_data.normal.z = -sign(ray_direction.z);
    //     }
    // }

    textureStore(output_texture, invocation_id.xy, color);
}

