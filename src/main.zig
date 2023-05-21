const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");

const log = std.log.scoped(.Engine);

fn glGetProcAddress(p: glfw.GLProc, proc: [:0]const u8) ?gl.FunctionPointer {
    _ = p;
    return glfw.getProcAddress(proc);
}

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

const Config = struct { width: u32 = 1920, height: u32 = 1080 };
const config = Config{};

pub fn main() !void {
    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }
    defer glfw.terminate();

    // Create our window
    const window = glfw.Window.create(config.width, config.height, "voxel-zig", null, null, .{
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
    const vertexShaderSource = @embedFile("shaders/triangle.vert").ptr;
    var vertexShader: gl.GLuint = gl.createShader(gl.VERTEX_SHADER);
    defer gl.deleteShader(vertexShader);
    gl.shaderSource(vertexShader, 1, &vertexShaderSource, null);
    gl.compileShader(vertexShader);

    // Report vertex shader errors
    {
        var success: gl.GLint = undefined;
        gl.getShaderiv(vertexShader, gl.COMPILE_STATUS, &success);

        var buffer: [512]u8 = undefined;
        gl.getShaderInfoLog(vertexShader, 512, null, &buffer);

        if (success != 1) {
            std.debug.print("Error compiling vertex shader! {s}\n", .{buffer});
        } else {
            std.debug.print("Successfully compiled vertex shader!\n", .{});
        }
    }

    // Create fragment shader
    var fragmentShaderSource = @embedFile("shaders/triangle.frag").ptr;
    var fragmentShader: gl.GLuint = gl.createShader(gl.FRAGMENT_SHADER);
    defer gl.deleteShader(fragmentShader);
    gl.shaderSource(fragmentShader, 1, &fragmentShaderSource, null);
    gl.compileShader(fragmentShader);

    // Report fragment shader errors
    {
        var success: gl.GLint = undefined;
        gl.getShaderiv(fragmentShader, gl.COMPILE_STATUS, &success);

        var buffer: [512]u8 = undefined;
        gl.getShaderInfoLog(fragmentShader, 512, null, &buffer);

        if (success != 1) {
            std.debug.print("Error compiling fragment shader! {s}\n", .{buffer});
        } else {
            std.debug.print("Successfully compiled fragment shader!\n", .{});
        }
    }

    // Create the shader program
    var shaderProgram: gl.GLuint = gl.createProgram();
    defer gl.deleteProgram(shaderProgram);
    gl.attachShader(shaderProgram, vertexShader);
    gl.attachShader(shaderProgram, fragmentShader);
    gl.linkProgram(shaderProgram);

    // Report shader program errors
    {
        var success: gl.GLint = undefined;
        gl.getProgramiv(shaderProgram, gl.LINK_STATUS, &success);

        var buffer: [512]u8 = undefined;
        gl.getProgramInfoLog(shaderProgram, 512, null, &buffer);

        if (success != 1) {
            std.debug.print("Error compiling shader program! {s}\n", .{buffer});
        } else {
            std.debug.print("Successfully compiled shader program!\n", .{});
        }
    }

    // Create and bind vertex buffer
    const vertices = [_]f32{ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0 };
    var VAO: gl.GLuint = undefined;
    gl.genVertexArrays(1, &VAO);
    defer gl.deleteVertexArrays(1, &VAO);

    var VBO: gl.GLuint = undefined;
    gl.genBuffers(1, &VBO);
    defer gl.deleteBuffers(1, &VBO);

    gl.bindVertexArray(VAO);

    gl.bindBuffer(gl.ARRAY_BUFFER, VBO);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(f32), null);
    gl.enableVertexAttribArray(0);

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        // input
        processInput(&window);

        // render
        gl.clearColor(0, 0, 0, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.useProgram(shaderProgram);
        gl.bindVertexArray(VAO);
        gl.drawArrays(gl.TRIANGLES, 0, 3);

        glfw.pollEvents();
        window.swapBuffers();
    }
}

fn processInput(window: *const glfw.Window) void {
    if (window.getKey(glfw.Key.escape) == glfw.Action.press) {
        window.setShouldClose(true);
    }
}
