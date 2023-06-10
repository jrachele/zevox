const std = @import("std");
const zmath = @import("zmath");

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

    pub fn deinit(self: Self) void {
        self.voxels.deinit();
    }
};

pub fn createVoxelGrid(allocator: std.mem.Allocator, dim: u32) !VoxelGrid {
    var grid = try VoxelGrid.init(allocator, dim, [3]f32{ 0.0, 0.0, 0.0 });
    grid.voxels.expandToCapacity();

    // Initialize the grid to a sphere
    const n = dim;
    const r = n - 5;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var j: u32 = 0;
        while (j < n) : (j += 1) {
            var k: u32 = 0;
            while (k < n) : (k += 1) {
                const index = (i * n * n) + (j * n) + k;
                const offset = @Vector(4, f32){ @intToFloat(f32, i), @intToFloat(f32, j), @intToFloat(f32, k), 0.0 };
                const adjusted = (offset * zmath.splat(@Vector(4, f32), 2.0)) - zmath.splat(@Vector(4, f32), @intToFloat(f32, n));

                if (@reduce(.Add, (zmath.lengthSq3(adjusted))) <= @intToFloat(f32, r * r)) {
                    grid.voxels.items[index] = Voxel{ .value = 1 };
                } else {
                    grid.voxels.items[index] = Voxel{};
                }
            }
        }
    }

    return grid;
}
