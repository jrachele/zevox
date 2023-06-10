const std = @import("std");
const root_path = "./assets/";

pub const fonts = struct {
    pub const roboto_medium = struct {
        pub const path = root_path ++ "fonts/Roboto-Medium.ttf";
        pub const bytes = @embedFile("fonts/Roboto-Medium.ttf");
    };
};

pub const shaders = struct {
    pub const quad = root_path ++ "shaders/quad.wgsl";
    pub const raytrace = root_path ++ "shaders/raytrace.wgsl";
};

pub const ShaderResource = struct {
    // 8MB limit
    const MAX_SHADER_BYTES: usize = 8 * 1024 * 1024;

    path: []const u8 = undefined,
    bytes: [:0]u8 = undefined,
    last_write_time: i128 = undefined,
    allocator: std.mem.Allocator = undefined,
    dirty: bool = true,

    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator, path: []const u8) anyerror!void {
        const file = try read(path);
        const stat = try file.stat();
        defer file.close();

        self.bytes = try file.readToEndAllocOptions(allocator, ShaderResource.MAX_SHADER_BYTES, null, @alignOf(u8), 0);
        self.path = path;
        self.allocator = allocator;
        self.last_write_time = stat.mtime;
        self.dirty = true;
    }

    pub fn read(path: []const u8) !std.fs.File {
        var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const abs_path = try std.fs.realpath(path, &path_buffer);

        return try std.fs.openFileAbsolute(abs_path, .{});
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.bytes);
    }

    pub fn data(self: *const Self) [*:0]const u8 {
        return @ptrCast([*:0]const u8, self.bytes.ptr);
    }

    pub fn update(self: *Self) !void {
        const file = try read(self.path);
        defer file.close();
        const stat = try file.stat();

        // Reload the file in memory
        if (stat.mtime > self.last_write_time) {
            self.last_write_time = stat.mtime;
            self.dirty = true;
            self.allocator.free(self.bytes);
            self.bytes = try file.readToEndAllocOptions(self.allocator, ShaderResource.MAX_SHADER_BYTES, null, @alignOf(u8), 0);
            std.debug.print("Reloaded file {s} following change!", .{self.path});
        }
    }
};

test "read" {
    _ = try ShaderResource.read("sdasdsa");
}
