const std = @import("std");
const mach = @import("libs/mach/build.zig");
const imgui = @import("libs/imgui/build.zig");
const zmath = @import("libs/zmath/build.zig");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const options = mach.Options{ .core = .{
        .gpu_dawn_options = .{
            .from_source = b.option(bool, "dawn-from-source", "Build Dawn from source") orelse false,
            .debug = b.option(bool, "dawn-debug", "Use a debug build of Dawn") orelse false,
        },
    } };

    // try ensureDependencies(b.allocator);

    const zmathModule = std.Build.ModuleDependency{
        .name = "zmath",
        .module = zmath.Package.build(b, .{
            .options = .{ .enable_cross_platform_determinism = true },
        }).zmath,
    };

    const imguiPkg = try imgui.Package(.{ .gpu_dawn = mach.gpu_dawn })
        .build(
        b,
        target,
        optimize,
        .{
            .options = .{
                .backend = .mach,
            },
        },
    );

    const imguiModule = std.Build.ModuleDependency{ .name = "imgui", .module = imguiPkg.zgui };

    const assetsModule = std.Build.ModuleDependency{
        .name = "assets",
        .module = b.createModule(
            .{
                .source_file = .{
                    .path = "assets/assets.zig",
                },
            },
        ),
    };

    const deps = [_]std.Build.ModuleDependency{ zmathModule, imguiModule, assetsModule };
    const app = try mach.App.init(b, .{
        .name = "voxel-zig",
        .src = "src/main.zig",
        .target = target,
        .optimize = optimize,
        .deps = deps[0..],
        .res_dirs = null,
        .watch_paths = &.{"src"},
        .use_freetype = null,
        .use_model3d = false,
    });

    imguiPkg.link(app.step);
    try app.link(options);
    app.install();

    const compile_step = b.step("voxel-zig", "Compile voxel-zig");
    compile_step.dependOn(&app.getInstallStep().?.step);

    const run_cmd = app.addRunArtifact();
    run_cmd.step.dependOn(compile_step);
    const run_step = b.step("run", "Run voxel-zig");
    run_step.dependOn(&run_cmd.step);
}

pub fn copyFile(src_path: []const u8, dst_path: []const u8) void {
    std.fs.cwd().makePath(std.fs.path.dirname(dst_path).?) catch unreachable;
    std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{}) catch unreachable;
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

fn ensureDependencies(allocator: std.mem.Allocator) !void {
    ensureGit(allocator);
    try ensureSubmodule(allocator, "libs/mach");
    try ensureSubmodule(allocator, "libs/zmath");
    try ensureSubmodule(allocator, "libs/zigimg");
}

fn ensureSubmodule(allocator: std.mem.Allocator, path: []const u8) !void {
    if (std.process.getEnvVarOwned(allocator, "NO_ENSURE_SUBMODULES")) |no_ensure_submodules| {
        defer allocator.free(no_ensure_submodules);
        if (std.mem.eql(u8, no_ensure_submodules, "true")) return;
    } else |_| {}
    var child = std.ChildProcess.init(&.{ "git", "submodule", "update", "--init", path }, allocator);
    child.cwd = sdkPath("/");
    child.stderr = std.io.getStdErr();
    child.stdout = std.io.getStdOut();

    _ = try child.spawnAndWait();
}

fn ensureGit(allocator: std.mem.Allocator) void {
    const result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "--version" },
    }) catch { // e.g. FileNotFound
        std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }
    if (result.term.Exited != 0) {
        std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
        std.process.exit(1);
    }
}
