@group(0) @binding(0)
var<storage, read> voxels: array<u32>;

@group(0) @binding(1)
var<storage, read_write> voxels_out: array<u32>;

struct RaytracingData {
    dim: u32,
    pos: vec3<f32>,
    camera_matrix: mat4x4<f32>,
    inverse_projection_matrix: mat4x4<f32>,
};

// TODO: Maybe I can get some kind of preprocessor for this
const VOXEL_SIZE: f32 = 1.0;
const EMPTY_VOXEL: u32 = 0u;
const VOXEL_TYPE_SAND = 0u;
const VOXEL_TYPE_WATER = 1u;

@group(0) @binding(2)
var<uniform> raytracing_data: RaytracingData;

fn get_index(index: vec3<i32>) -> u32 {
    let dim = i32(raytracing_data.dim);
    return u32((index.x * dim * dim) + (index.y * dim) + index.z);
}

fn out_of_bounds(index: vec3<i32>) -> bool {
    let dim = i32(raytracing_data.dim);
    return index.x < 0 || index.x >= dim || index.y < 0 || index.y >= dim || index.z < 0 || index.z >= dim;
}

fn handle_sand(index: vec3<i32>) {
    if out_of_bounds(index) {
        return;
    }

    let current_voxel = voxels[get_index(index)];
    if current_voxel == EMPTY_VOXEL {
        // voxels_out[get_index(index)] = current_voxel;
        return;
    }

    let below_block_index = vec3<i32>(index.x, index.y - 1, index.z);

    if !out_of_bounds(below_block_index) {
        let below_block = voxels[get_index(below_block_index)];
        // Ensure we have no write conflicts
        if voxels_out[get_index(below_block_index)] == EMPTY_VOXEL {
            voxels_out[get_index(index)] = EMPTY_VOXEL;
            voxels_out[get_index(below_block_index)] = current_voxel;
            return;
        }
        // if (voxels_out[get_index(below_block_index)] == EMPTY_VOXEL) {
        //     voxels_out[get_index(index)] = EMPTY_VOXEL;
        //     voxels_out[get_index(below_block_index)] = current_voxel;
        //     return;
        // }

        // Let's try to move to a different spot in the xz plane at y-1
        // use index.x and index.y as hash inputs for the randomizer
        for (var i = -1; i <= 1; i++) {
            for (var j = -1; j <= 1; j++) {
                let x_offset = i;
                let z_offset = j;
                let side_block_index = vec3<i32>(index.x + x_offset, index.y - 1, index.z + z_offset);
                if !out_of_bounds(side_block_index) {
                    let side_block = voxels[get_index(side_block_index)];
                    // Ensure no conflicts
                    if voxels_out[get_index(side_block_index)] == EMPTY_VOXEL {
                        voxels_out[get_index(index)] = EMPTY_VOXEL;
                        voxels_out[get_index(side_block_index)] = current_voxel;
                        return;
                    }
                }
            }
        }
        // let x_offset = random_int(u32(index.x), -1, 1);
        // let z_offset = random_int(u32(index.y), -1, 1);
        // let side_block_index = vec3<i32>(index.x + x_offset, index.y - 1, index.z + z_offset);
        // if (!out_of_bounds(side_block_index)) {
        //     let side_block = voxels[get_index(side_block_index)];
        //     // Ensure no conflicts
        //     if (voxels_out[get_index(side_block_index)] == EMPTY_VOXEL) {
        //         voxels_out[get_index(index)] = EMPTY_VOXEL;
        //         voxels_out[get_index(side_block_index)] = current_voxel;
        //         return;
        //     }
        // }
    }

    // If we weren't able to move the block before, store its current state
    voxels_out[get_index(index)] = current_voxel;
}

@compute @workgroup_size(4, 4, 4)
fn main(@builtin(global_invocation_id) invocation_id: vec3<u32>, @builtin(local_invocation_id) invocation_id_local: vec3<u32>, @builtin(num_workgroups) num_workgroups: vec3<u32>, @builtin(workgroup_id) workgroup_id: vec3<u32>) {
    var index = vec3<i32>(invocation_id);
    handle_voxel_physics(index, voxels[get_index(index)]);
    // for (var i = 0u; i < dim; i++) {
    //     for (var j = 0u; j < dim; j++) {
    //         for (var k = 0u; k < dim; k++) {
    //             var index = vec3<i32>(vec3<u32>(i, j, k));
    //             handle_voxel_physics(index, voxels[get_index(index)]);
    //         }
    //     }
    // }

    // TODO: Move brush manipulation to a separate shader
    // var selected = vec3<i32>(selected);
    // if (player_data.mouse_click & 1u) == 1u {
    //     // Left click
    //     voxels_out[get_index(selected)] = 0u;
    // }
    // if ((player_data.mouse_click >> 1u) & 1u) == 1u {
    //     // Middle click
    // }
    // if ((player_data.mouse_click >> 2u) & 1u) == 1u {
    //     // Right click
    //     var normal = vec3<i32>(normal);
    //     selected = selected + normal;
    //     // Black sand
    //     voxels_out[get_index(selected)] = 1u << 9u;
    // }
}

fn handle_voxel_physics(index: vec3<i32>, voxel: u32) {
    if voxel == EMPTY_VOXEL {
        return;
    }

    handle_sand(index);
}
