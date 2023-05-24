// Shitty GPU subsystem for OpenGL
// Likely needs major revisions to be usable

const std = @import("std");
const gl = @import("gl");
const shaderImport = @import("shader.zig");

const Shader = shaderImport.Shader;
const ShaderProgram = shaderImport.ShaderProgram;
const ShaderType = shaderImport.ShaderType;

const GPUError = error{
    BufferAlreadyExists,
    TextureAlreadyExists,
    ProgramAlreadyExists,
    TextureLimitExceeded,
    ProgramNotFound,
    BufferNotFound,
    TextureNotFound,
    UniformTypeInvalid,
};

const BufferType = enum { Uniform, Storage };

const Vertex = struct {
    id: gl.GLuint,
    stride: i32,
};

// Provides helper methods for interfacing with the GPU
pub const GPU = struct {
    const BufferMap = std.StringHashMap(gl.GLuint);
    const TextureMap = std.StringHashMap(gl.GLuint);
    const VertexMap = std.StringHashMap(Vertex);
    const ProgramMap = std.StringHashMap(ShaderProgram);

    allocator: *const std.mem.Allocator,
    buffers: BufferMap,
    textures: TextureMap,
    vertices: VertexMap,
    programs: ProgramMap,

    vao: gl.GLuint = 0,

    pub fn init(allocator: std.mem.Allocator) GPU {
        var self = GPU{ .allocator = &allocator, .buffers = BufferMap.init(allocator), .textures = TextureMap.init(allocator), .programs = ProgramMap.init(allocator), .vertices = VertexMap.init(allocator) };
        return self;
    }

    pub fn deinit(self: *GPU) void {
        for (self.buffers.keys()) |key| {
            self.allocator.free(key);
        }

        for (self.textures.keys()) |key| {
            self.allocator.free(key);
        }

        for (self.vertices.keys()) |key| {
            self.allocator.free(key);
        }

        for (self.programs.keys()) |key| {
            self.allocator.free(key);
        }
    }

    // Add a storage of a particular name
    // You should use a packed struct here with data to ensure
    // That you get the proper alignment as desired by OpenGL
    pub fn initStorageBuffer(self: *GPU, name: []const u8, size: isize, data: ?*const anyopaque) !void {
        if (self.buffers.contains(name)) {
            return GPUError.BufferAlreadyExists;
        }

        var bufferId: gl.GLuint = undefined;
        gl.genBuffers(1, &bufferId);
        gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, bufferId);
        gl.bufferData(gl.SHADER_STORAGE_BUFFER, size, data, gl.STATIC_DRAW);
        gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, 0);

        var nameString = try self.allocator.dupe(u8, name);
        try self.buffers.put(nameString, bufferId);
    }

    // This is a bit unfortunate... we can't bind the locations of these vertices at draw time, they are permanently assigned to each VAO
    // which is different from how other buffers are bound.
    pub fn initVertexBuffer(self: *GPU, name: []const u8, size: isize, data: ?*const anyopaque, stride: i32, location: u32) !void {
        if (self.vertices.contains(name)) {
            return GPUError.BufferAlreadyExists;
        }

        const num_vertices = self.vertices.count();
        if (num_vertices == 0) {
            gl.genVertexArrays(1, &self.vao);
        }
        gl.bindVertexArray(self.vao);

        var bufferId: gl.GLuint = undefined;
        gl.genBuffers(1, &bufferId);
        gl.bindBuffer(gl.ARRAY_BUFFER, bufferId);
        gl.bufferData(gl.ARRAY_BUFFER, size, data, gl.STATIC_DRAW);
        gl.enableVertexAttribArray(location);
        gl.vertexAttribPointer(location, stride, gl.FLOAT, gl.FALSE, 0, null);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        var nameString = try self.allocator.dupe(u8, name);
        try self.vertices.put(nameString, .{ .id = bufferId, .stride = stride });
    }

    // Add a 2d texture of a certain name
    pub fn initTexture2D(self: *GPU, name: []const u8, width: i32, height: i32) !void {
        if (self.textures.contains(name)) {
            return GPUError.TextureAlreadyExists;
        }

        const numTextures = self.textures.count();
        if (numTextures > 32) {
            return GPUError.TextureLimitExceeded;
        }

        var bufferId: gl.GLuint = undefined;
        gl.genTextures(1, &bufferId);
        gl.bindTexture(gl.TEXTURE_2D, bufferId);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, width, height, 0, gl.RGBA, gl.FLOAT, null);
        gl.bindTexture(gl.TEXTURE_2D, 0);

        var nameString = try self.allocator.dupe(u8, name);
        try self.textures.put(nameString, bufferId);
    }

    // Add a shader program to the GPU subsystem
    pub fn addShaderProgram(self: *GPU, name: []const u8, program: ShaderProgram) !void {
        if (self.programs.contains(name)) {
            return GPUError.ProgramAlreadyExists;
        }

        var nameString = try self.allocator.dupe(u8, name);
        try self.programs.put(nameString, program);
    }

    pub fn bindUniform(self: *GPU, shader_program: []const u8, uniform_name: []const u8, uniform_data: anytype) !void {
        var program = self.programs.get(shader_program) orelse {
            return GPUError.ProgramNotFound;
        };

        gl.useProgram(program.get());

        const location = gl.getUniformLocation(program.get(), uniform_name.ptr);
        const T = @TypeOf(uniform_data);
        switch (T) {
            i32 => gl.uniform1i(location, uniform_data),
            [2]f32 => gl.uniform2f(location, uniform_data[0], uniform_data[1]),
            else => {
                return GPUError.UniformTypeInvalid;
            },
        }
    }

    pub fn bindStorageBuffer(self: *GPU, shader_program: []const u8, buffer_name: []const u8, location: u32) !void {
        var program = self.programs.get(shader_program) orelse {
            return GPUError.ProgramNotFound;
        };

        var buffer = self.buffers.get(buffer_name) orelse {
            return GPUError.BufferNotFound;
        };

        gl.useProgram(program.get());

        gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, location, buffer);
    }

    pub fn bindTexture(self: *GPU, shader_program: []const u8, texture_name: []const u8, texture_index: u32, location: u32) !void {
        var program = self.programs.get(shader_program) orelse {
            return GPUError.ProgramNotFound;
        };

        var texture = self.textures.get(texture_name) orelse {
            return GPUError.TextureNotFound;
        };

        gl.useProgram(program.get());

        const texture_location = gl.TEXTURE0 + texture_index;
        gl.activeTexture(texture_location);
        gl.bindImageTexture(location, texture, 0, gl.FALSE, 0, gl.WRITE_ONLY, gl.RGBA32F);
    }

    pub fn bindVertices(self: *GPU, shader_program: []const u8) !void {
        var program = self.programs.get(shader_program) orelse {
            return GPUError.ProgramNotFound;
        };

        gl.useProgram(program.get());
        gl.bindVertexArray(self.vao);
    }
};
