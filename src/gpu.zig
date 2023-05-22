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
};

const Buffer = struct {
    id: gl.GLuint = 0,
    bufferType: BufferType = BufferType.Uniform,
};

const BufferType = enum { Uniform, Storage };

const Texture = struct {
    id: gl.GLuint = 0,
    glId: gl.GLenum = gl.TEXTURE0,
};

// Provides helper methods for interfacing with the GPU
pub const GPU = struct {
    const BufferMap = std.StringHashMap(Buffer);
    const TextureMap = std.StringHashMap(Texture);
    const ProgramMap = std.StringHashMap(ShaderProgram);
    const VertexMap = std.StringHashMap(gl.GLuint);

    buffers: BufferMap,
    textures: TextureMap,
    programs: ProgramMap,
    vertices: VertexMap,
    vao: gl.GLuint = 0,

    pub fn init(allocator: std.mem.Allocator) GPU {
        var self = GPU{ .buffers = BufferMap.init(allocator), .textures = TextureMap.init(allocator), .programs = ProgramMap.init(allocator), .vertices = VertexMap.init(allocator) };
        return self;
    }

    // Add a uniform of a particular name
    // You should use a packed struct here with data to ensure
    // That you get the proper alignment as desired by OpenGL
    pub fn add_uniform(self: *GPU, name: []const u8, size: isize, data: ?*const anyopaque) !void {
        if (self.buffers.contains(name)) {
            return GPUError.BufferAlreadyExists;
        }

        var bufferId: gl.GLuint = undefined;
        gl.genBuffers(1, &bufferId);
        gl.bindBuffer(gl.UNIFORM_BUFFER, bufferId);
        // TODO: Maybe I still need to have bindBufferBase() coupled with this?
        gl.bufferData(gl.UNIFORM_BUFFER, size, data, gl.STATIC_DRAW);
        gl.bindBuffer(gl.UNIFORM_BUFFER, 0);

        var nameString = std.ArrayList(u8).init(self.buffers.allocator);
        try nameString.appendSlice(name);
        try self.buffers.put(nameString.items, Buffer{ .id = bufferId, .bufferType = BufferType.Uniform });
    }

    // Update an existing uniform of a particular name
    pub fn update_uniform(self: *GPU, name: []const u8, size: isize, data: ?*const anyopaque) !void {
        var uniform = self.buffers.get(name) orelse {
            return GPUError.BufferNotFound;
        };
        gl.bindBuffer(gl.UNIFORM_BUFFER, uniform.id);
        gl.bufferSubData(gl.UNIFORM_BUFFER, 0, size, data);
        gl.bindBuffer(gl.UNIFORM_BUFFER, 0);
    }

    // Add a storage of a particular name
    // You should use a packed struct here with data to ensure
    // That you get the proper alignment as desired by OpenGL
    pub fn add_storage(self: *GPU, name: []const u8, size: isize, data: ?*const anyopaque) !void {
        if (self.buffers.contains(name)) {
            return GPUError.BufferAlreadyExists;
        }

        var bufferId: gl.GLuint = undefined;
        gl.genBuffers(1, &bufferId);
        gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, bufferId);
        gl.bufferData(gl.SHADER_STORAGE_BUFFER, size, data, gl.STATIC_DRAW);
        gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, 0);

        var nameString = try self.buffers.allocator.dupe(u8, name);
        try self.buffers.put(nameString, Buffer{ .id = bufferId, .bufferType = BufferType.Storage });
    }

    // Add a vertex buffer with a particular name
    // This will be added to a vertex array object automatically
    pub fn add_vertex_buffer(self: *GPU, name: []const u8, size: isize, data: ?*const anyopaque, stride: i32) !void {
        if (self.vertices.contains(name)) {
            return GPUError.BufferAlreadyExists;
        }

        const numVertices = self.vertices.count();

        if (numVertices == 0) {
            gl.genVertexArrays(1, &self.vao);
        }

        var bufferId: gl.GLuint = undefined;
        gl.genBuffers(1, &bufferId);
        // TODO: Perhaps allow multiple VAOs
        // but this is not intended to be a general OpenGL wrapper so w/e
        gl.bindVertexArray(self.vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, bufferId);
        gl.bufferData(gl.ARRAY_BUFFER, size, data, gl.STATIC_DRAW);
        gl.vertexAttribPointer(numVertices, stride, gl.FLOAT, gl.FALSE, 0, null);
        gl.enableVertexAttribArray(numVertices);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        var nameString = try self.vertices.allocator.dupe(u8, name);
        try self.vertices.put(nameString, bufferId);
    }

    // Add a 2d texture of a certain name
    pub fn add_texture_2d(self: *GPU, name: []const u8, width: i32, height: i32) !void {
        if (self.textures.contains(name)) {
            return GPUError.TextureAlreadyExists;
        }

        const numTextures = self.textures.count();
        if (numTextures > 32) {
            return GPUError.TextureLimitExceeded;
        }

        var bufferId: gl.GLuint = undefined;
        var textureId = gl.TEXTURE0 + numTextures;
        gl.genTextures(1, &bufferId);
        gl.activeTexture(textureId);
        gl.bindTexture(gl.TEXTURE_2D, bufferId);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, width, height, 0, gl.RGBA, gl.FLOAT, null);
        gl.bindTexture(gl.TEXTURE_2D, 0);

        var nameString = try self.textures.allocator.dupe(u8, name);
        try self.textures.put(nameString, Texture{
            .id = bufferId,
            .glId = textureId,
        });
    }

    // Add a shader program to the GPU subsystem
    pub fn add_shader_program(self: *GPU, name: []const u8, program: ShaderProgram) !void {
        if (self.programs.contains(name)) {
            return GPUError.ProgramAlreadyExists;
        }

        var nameString = try self.programs.allocator.dupe(u8, name);
        try self.programs.put(nameString, program);
    }

    // Performs bindings needed for a traditional draw pipeline.
    // Will bind all vertices that are present!
    // If you supply the uniform_block name,
    // all uniforms will be bound in your shaders under said name
    pub fn bind_draw(self: *GPU, program_name: []const u8, binds: [][]const u8, uniform_block: ?[]const u8) !void {
        var program = self.programs.get(program_name);

        if (program == null) {
            return GPUError.ProgramNotFound;
        }

        // Bind vertices first
        gl.bindVertexArray(self.vao);

        // Ensure we increment our bindings offset from the vertex buffers and potentially the uniform block
        var start_index = self.vertices.count();

        // If we want our uniforms present we can put them in this block
        if (uniform_block) |name| {
            var blockLocation = gl.getUniformBlockIndex(program.?.get(), name.ptr);
            gl.uniformBlockBinding(program.?.get(), blockLocation, start_index);
        }

        gl.useProgram(program.?.get());

        try self.bind_buffers(start_index, binds);
    }

    fn bind_buffers(self: *GPU, start_index: u32, buffers: [][]const u8) !void {
        var index = start_index;
        for (buffers) |buffer| {
            var value = self.buffers.get(buffer);
            if (value) |bufferObj| {
                switch (bufferObj.bufferType) {
                    BufferType.Uniform => {
                        gl.bindBufferBase(gl.UNIFORM_BUFFER, index, bufferObj.id);
                    },
                    BufferType.Storage => {
                        gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, index, bufferObj.id);
                    },
                }
                index += 1;
                continue;
            }

            var vertex = self.vertices.get(buffer);
            if (vertex) |_| {
                // For now, the VBOs don't get explicitly bound
                // instead the VAOs do above
                continue;
            }

            var texture = self.textures.get(buffer);
            if (texture) |textureObj| {
                gl.activeTexture(textureObj.glId);
                gl.bindImageTexture(index, textureObj.id, 0, gl.FALSE, 0, gl.WRITE_ONLY, gl.RGBA32F);
                index += 1;
                continue;
            }

            return GPUError.BufferNotFound;
        }
    }
};
