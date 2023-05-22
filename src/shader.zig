// Shader loader, does not support hot-reloading

const std = @import("std");
const gl = @import("gl");

// Struct for simplifying the loading of shaders
pub const Shader = struct {
    // If supplied, the shader will read the contents in the path provided
    path: ?[]const u8,
    raw: ?[]const u8,
    shaderType: ShaderType,
    id: gl.GLuint,

    pub fn fromPath(shaderType: ShaderType, comptime path: []const u8) !Shader {
        var self = Shader{ .shaderType = shaderType, .path = path, .raw = null, .id = 0 };

        const shaderSource = @embedFile(path).ptr;
        var shaderId = gl.createShader(glTypeFromShaderType(shaderType));
        self.id = shaderId;

        if (createShader(shaderId, &shaderSource)) {
            return self;
        } else {
            return ShaderError.CompileShader;
        }
    }

    pub fn fromRaw(shaderType: ShaderType, comptime raw: []const u8) !Shader {
        var self = Shader{ .shaderType = shaderType, .path = null, .raw = raw, .id = 0 };

        const shaderSource = raw.ptr;
        var shaderId = gl.createShader(glTypeFromShaderType(shaderType));
        self.id = shaderId;

        if (createShader(shaderId, &shaderSource)) {
            return self;
        } else {
            return ShaderError.CompileShader;
        }
    }

    pub fn delete(self: Shader) void {
        gl.deleteShader(self.id);
    }

    pub fn get(self: Shader) gl.GLuint {
        return self.id;
    }

    fn createShader(shaderId: gl.GLuint, shaderSource: *const [*]const u8) bool {
        gl.shaderSource(shaderId, 1, shaderSource, null);
        gl.compileShader(shaderId);

        // Report shader errors
        {
            var success: gl.GLint = undefined;
            gl.getShaderiv(shaderId, gl.COMPILE_STATUS, &success);

            var buffer: [512]u8 = undefined;
            gl.getShaderInfoLog(shaderId, 512, null, &buffer);

            if (success != 1) {
                std.debug.print("Error compiling shader {d}! {s}\n", .{ shaderId, buffer });
                return false;
            } else {
                std.debug.print("Successfully compiled shader {d}!\n", .{shaderId});
                return true;
            }
        }
    }

    fn glTypeFromShaderType(shaderType: ShaderType) gl.GLenum {
        return switch (shaderType) {
            ShaderType.Vertex => gl.VERTEX_SHADER,
            ShaderType.Fragment => gl.FRAGMENT_SHADER,
            ShaderType.Compute => gl.COMPUTE_SHADER,
        };
    }
};

/// Struct to facilitate the creation of shader programs
pub const ShaderProgram = struct {
    id: gl.GLuint = 0,

    pub fn fromShaders(shaders: []const Shader) !ShaderProgram {
        var shaderProgram = ShaderProgram{ .id = gl.createProgram() };

        for (shaders) |shader| {
            gl.attachShader(shaderProgram.id, shader.get());
        }

        gl.linkProgram(shaderProgram.id);

        // Report shader program errors
        var success: gl.GLint = undefined;
        gl.getProgramiv(shaderProgram.id, gl.LINK_STATUS, &success);

        var buffer: [512]u8 = undefined;
        gl.getProgramInfoLog(shaderProgram.id, 512, null, &buffer);

        if (success != 1) {
            std.debug.print("Error compiling shader program {d}! {s}\n", .{ shaderProgram.id, buffer });
            return ShaderError.CompileProgram;
        } else {
            std.debug.print("Successfully compiled shader program {d}!\n", .{shaderProgram.id});
            return shaderProgram;
        }
    }

    pub fn delete(self: ShaderProgram) void {
        gl.deleteProgram(self.id);
    }

    pub fn get(self: ShaderProgram) gl.GLuint {
        return self.id;
    }
};

pub const ShaderType = enum { Vertex, Fragment, Compute };

pub const ShaderError = error{ CompileShader, CompileProgram };
