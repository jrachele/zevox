const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");

const shader = @import("shader.zig");
const gameState = @import("gamestate.zig");

const log = std.log.scoped(.Engine);

const Config = struct { width: u32 = 1920, height: u32 = 1080 };
const config = Config{};

const RunTimeStatistics = struct {
    updates: u64 = 0,
    frames: u64 = 0,
};

// TODO: Either clean this up elegantly or use flecs
// the latter is ideal but may be a lot of work

// Resources
var window: glfw.Window = undefined;
var time = gameState.Time{ .time = 0.0, .deltaTime = 0.0, .limitFPS = 1.0 / 60.0 };
var stats = RunTimeStatistics{};

// Render resources TODO: refactor
var VAO: gl.GLuint = undefined;
var VBO: gl.GLuint = undefined;
var pixelDrawPipeline: shader.ShaderProgram = undefined;

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

    // Create vertex shader
    const vertexShader = try shader.Shader.fromPath(shader.ShaderType.Vertex, "shaders/triangle.vert");
    defer vertexShader.delete();

    const fragmentShader = try shader.Shader.fromPath(shader.ShaderType.Fragment, "shaders/triangle.frag");
    defer fragmentShader.delete();

    // Create the shader program
    var shaders = [_]shader.Shader{ vertexShader, fragmentShader };
    pixelDrawPipeline = try shader.ShaderProgram.fromShaders(shaders[0..]);
    defer pixelDrawPipeline.delete();

    // Create and bind vertex buffer
    gl.genVertexArrays(1, &VAO);
    defer gl.deleteVertexArrays(1, &VAO);

    gl.genBuffers(1, &VBO);
    defer gl.deleteBuffers(1, &VBO);

    gl.bindVertexArray(VAO);

    gl.bindBuffer(gl.ARRAY_BUFFER, VBO);

    const vertices = [_]f32{ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0 };
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(f32), null);
    gl.enableVertexAttribArray(0);

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
            update();
            stats.updates += 1;
            time.deltaTime -= 1;
        }

        // render
        render();
        glfw.pollEvents();
        window.swapBuffers();
    }
}

fn update() void {
    processInput();
}

fn render() void {
    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    // TODO: Abstract pipelines to allow to simply say
    // pipeline.dispatch();
    // you should be able to say
    // pipeline.bindArray("vertex buffer")
    // and it will pull from a hashmap of known arrays
    const cpuSideValueLocation = gl.getUniformLocation(pixelDrawPipeline.get(), "rotation");
    gl.useProgram(pixelDrawPipeline.get());
    const rotationXY = processRotation();
    gl.uniform2f(cpuSideValueLocation, rotationXY[0], rotationXY[1]);
    gl.bindVertexArray(VAO);
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
