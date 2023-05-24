const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");

const shader = @import("shader.zig");
const gameState = @import("gamestate.zig");
const gpuImport = @import("gpu.zig");
const log = std.log.scoped(.Engine);

const Config = struct { width: u32 = 1920, height: u32 = 1080 };
const config = Config{};

const RunTimeStatistics = struct {
    updates: u64 = 0,
    frames: u64 = 0,
};

// Resources
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// defer gpa.deinit();

var gpu: gpuImport.GPU = gpuImport.GPU.init(allocator);
var window: glfw.Window = undefined;
var time = gameState.Time{ .time = 0.0, .deltaTime = 0.0, .limitFPS = 1.0 / 60.0 };
var stats = RunTimeStatistics{};

// Test resources
var rotation: f32 = 0.0;

fn glGetProcAddress(p: glfw.GLProc, proc: [:0]const u8) ?gl.FunctionPointer {
    _ = p;
    return glfw.getProcAddress(proc);
}

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

export fn glDebugOutput(source: gl.GLenum, output_type: gl.GLenum, id: gl.GLuint, severity: gl.GLenum, length: gl.GLsizei, message: [*:0]const u8, userParam: ?*anyopaque) void {
    std.debug.print("[OpenGL] {s}\n", .{message});
    _ = userParam;
    _ = length;
    _ = severity;
    _ = id;
    _ = output_type;
    _ = source;
}

pub fn main() !void {
    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }
    defer glfw.terminate();

    // Create our window
    window = glfw.Window.create(config.width, config.height, "voxel-zig", null, null, .{
        .opengl_profile = .opengl_core_profile,
        .context_version_major = 4,
        .context_version_minor = 5,
        .context_debug = true,
    }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };
    defer window.destroy();

    window.setAttrib(glfw.Window.Attrib.resizable, false);
    window.setAttrib(glfw.Window.Attrib.floating, true);

    glfw.makeContextCurrent(window);

    const proc: glfw.GLProc = undefined;
    try gl.load(proc, glGetProcAddress);

    // Setup debug output
    gl.enable(gl.DEBUG_OUTPUT);
    gl.enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);
    gl.debugMessageCallback(&glDebugOutput, null);

    const triangleVert = try shader.Shader.fromPath(shader.ShaderType.Vertex, "shaders/triangle.vert");
    const triangleFrag = try shader.Shader.fromPath(shader.ShaderType.Fragment, "shaders/triangle.frag");

    var shaders = [_]shader.Shader{ triangleVert, triangleFrag };
    const triangleProgram = try shader.ShaderProgram.fromShaders(shaders[0..]);
    try gpu.addShaderProgram("triangle", triangleProgram);

    const vertices = [_]f32{ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0 };
    try gpu.initVertexBuffer("vertex", @sizeOf(@TypeOf(vertices)), &vertices, 3, 0);

    // Creates voxel grid in and voxel grid out
    try createStorageBuffer();

    // Creates a texture for writing
    try gpu.initTexture2D("texture out", @as(i32, config.width), @as(i32, config.height));

    const raycastComp = try shader.Shader.fromPath(shader.ShaderType.Compute, "shaders/raytrace.comp");

    var raytraceShaders = [_]shader.Shader{raycastComp};
    var raytraceProgram = try shader.ShaderProgram.fromShaders(raytraceShaders[0..]);
    try gpu.addShaderProgram("raytrace", raytraceProgram);

    var startTime = glfw.getTime();
    var lastFrameTime = startTime;

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        var nowTime = glfw.getTime();
        time.time = nowTime - startTime;
        time.deltaTime += (nowTime - lastFrameTime) / time.limitFPS;
        lastFrameTime = nowTime;

        // Have deltaTime accumulate and use a while loop in case the frames dip
        // heavily below 60 and we need to catch up
        while (time.deltaTime >= 1.0) {
            // Perform physics and input handling here
            try update();
            stats.updates += 1;
            time.deltaTime -= 1;
        }

        // render
        try render();
        glfw.pollEvents();
        window.swapBuffers();
    }
}

fn update() !void {
    processInput();
}

fn render() !void {
    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    {
        try gpu.bindStorageBuffer("raytrace", "voxel grid in", 0);
        try gpu.bindTexture("raytrace", "texture out", 0, 1);
        gl.dispatchCompute(config.width / 8, config.height / 8, 1);
    }

    gl.memoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT);

    try gpu.bindVertices("triangle");
    try gpu.bindTexture("triangle", "texture out", 0, 1);
    try gpu.bindUniform("triangle", "rotation", processRotation());
    gl.drawArrays(gl.TRIANGLES, 0, 3);
}

fn processInput() void {
    if (window.getKey(glfw.Key.escape) == glfw.Action.press) {
        window.setShouldClose(true);
    }

    if (window.getKey(glfw.Key.left) == glfw.Action.press) {
        rotation -= 1.0;
    }

    if (window.getKey(glfw.Key.right) == glfw.Action.press) {
        rotation += 1.0;
    }
}

fn processRotation() [2]f32 {
    return [2]f32{ 0.5 * std.math.sin(rotation), 0.5 * std.math.cos(rotation) };
}

const VoxelBufferSize: u32 = 128;

fn createStorageBuffer() !void {
    const memory = try allocator.alloc(u32, VoxelBufferSize * VoxelBufferSize * VoxelBufferSize);
    defer allocator.free(memory);

    // create a sphere as an example
    const n = VoxelBufferSize;
    const r = (n - 1);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var j: u32 = 0;
        while (j < n) : (j += 1) {
            var k: u32 = 0;
            while (k < n) : (k += 1) {
                const index = (i * n * n) + (j * n) + k;
                if (i * i + j * j + k * k <= r * r) {
                    memory[index] = 1;
                } else {
                    memory[index] = 0;
                }
            }
        }
    }

    const voxelGridSize = @sizeOf(u32) * @as(isize, @truncate(u32, memory.len));
    try gpu.initStorageBuffer("voxel grid in", voxelGridSize, memory.ptr);
    try gpu.initStorageBuffer("voxel grid out", voxelGridSize, memory.ptr);
}
