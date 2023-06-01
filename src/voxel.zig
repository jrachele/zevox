const std = @import("std");

pub const Voxel = struct {
    value: u32 = 0,
};

pub const VoxelGrid = struct {
    dim: u32 = 0,
    pos: [3]f32 = [_]f32{ 0.0, 0.0, 0.0 },
    voxels: std.ArrayList(Voxel),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, dim: u32, pos: [3]f32) !Self {
        return Self{
            .dim = dim,
            .pos = pos,
            .voxels = try std.ArrayList(Voxel).initCapacity(allocator, @as(usize, dim * dim * dim)),
            .allocator = allocator,
        };
    }
};

pub fn createVoxelGrid(allocator: std.mem.Allocator, dim: u32) !VoxelGrid {
    var grid = try VoxelGrid.init(allocator, dim, [3]f32{ 0.0, 0.0, 0.0 });
    grid.voxels.expandToCapacity();

    // Initialize the grid to a sphere
    const n = dim;
    const r = n - 1;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var j: u32 = 0;
        while (j < n) : (j += 1) {
            var k: u32 = 0;
            while (k < n) : (k += 1) {
                const index = (i * n * n) + (j * n) + k;
                if ((i * i) + (j * j) + (k * k) <= (r * r)) {
                    grid.voxels.items[index] = Voxel{ .value = 1 };
                } else {
                    grid.voxels.items[index] = Voxel{};
                }
            }
        }
    }

    return grid;
}
