const assets = @import("assets");
const std = @import("std");
const mach = @import("mach");
const zmath = @import("zmath");

// local includes
const input = @import("input.zig");
const imgui = @import("imgui.zig");
const ui = @import("ui.zig");
const voxel = @import("voxel.zig");
const prelude = @import("prelude.zig");

const Camera = @import("camera.zig").Camera;
const InputData = input.InputData;
const ShaderResource = assets.ShaderResource;

const gpu = mach.gpu;
pub const App = @This();

const GameConfig = struct {
    screen_width: u32 = 1920,
    screen_height: u32 = 1080,
    voxel_grid_dim: u32 = 256,
    workgroup_size: u32 = 8,
};

const Time = struct {
    time: f32 = 0.0,
    delta_time: f32 = 0.0,
};

const RaytracingData = extern struct {
    dim: u32 align(16) = 0,
    pos: prelude.Vec3 align(16) = [_]f32{ 0.0, 0.0, 0.0 },
    camera_matrix: prelude.Mat4 align(16),
    inverse_projection_matrix: prelude.Mat4 align(16),
};

test "raytracing data size" {
    try std.testing.expect(@sizeOf(RaytracingData) == 144);
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

allocator: std.mem.Allocator,
core: mach.Core,
timer: mach.Timer,
time: Time,
game_config: GameConfig,
input_data: InputData,
camera: Camera,

// TODO: Refactor shader resources into more intelligent asset pipeline
raytracing_data: RaytracingData,
raytracing_data_buffer: *gpu.Buffer,
raytracing_shader: ShaderResource,
raytracing_pipeline: *gpu.ComputePipeline,
raytracing_bind_group: *gpu.BindGroup,
render_shader: ShaderResource,
render_pipeline: *gpu.RenderPipeline,
render_bind_group: *gpu.BindGroup,
texture: *gpu.Texture,
voxel_grid_buffer: *gpu.Buffer,
queue: *gpu.Queue,

pub fn init(app: *App) !void {
    app.allocator = gpa.allocator();
    app.game_config = GameConfig{};
    app.input_data = InputData{};
    app.setupCamera();
    app.timer = try mach.Timer.start();
    app.time = Time{};

    try app.core.init(app.allocator, .{ .title = "Zoxel", .size = .{
        .width = app.game_config.screen_width,
        .height = app.game_config.screen_height,
    } });

    // Disable VSync cause I ain't no RAT.
    app.core.setVSync(.none);

    // Raytracing compute pipeline
    try app.raytracing_shader.init(app.allocator, assets.shaders.raytrace);

    // Voxel grid
    const voxel_grid = try voxel.createVoxelGrid(app.allocator, app.game_config.voxel_grid_dim);
    defer voxel_grid.deinit();
    const voxel_grid_bytes = voxel_grid.voxels.items;
    const voxel_grid_size = voxel_grid_bytes.len * @sizeOf(voxel.Voxel);
    app.voxel_grid_buffer = app.core.device().createBuffer(&gpu.Buffer.Descriptor{
        .label = "voxel_grid",
        .usage = .{
            .storage = true,
            .copy_dst = true,
        },
        .size = voxel_grid_size,
    });

    app.core.device().getQueue().writeBuffer(app.voxel_grid_buffer, 0, voxel_grid_bytes[0..]);

    // Texture
    const img_size = gpu.Extent3D{
        .width = app.game_config.screen_width,
        .height = app.game_config.screen_height,
    };

    app.texture = app.core.device().createTexture(&.{
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .storage_binding = true,
            .copy_dst = true,
        },
    });

    app.raytracing_data_buffer = app.core.device().createBuffer(&gpu.Buffer.Descriptor{
        .label = "raytracing_data",
        .usage = .{
            .uniform = true,
            .copy_dst = true,
        },
        .size = @sizeOf(RaytracingData),
    });

    // Render pipeline
    try app.render_shader.init(app.allocator, assets.shaders.quad);
    const shader_module = app.core.device().createShaderModuleWGSL(
        assets.shaders.quad,
        app.render_shader.data(),
    );
    defer shader_module.release();

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = app.core.descriptor().format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vert_main",
        },
    };

    imgui.init(app.allocator);
    imgui.mach_backend.init(&app.core, app.core.device(), app.core.descriptor().format, .{});

    const font_size = 18.0;
    const font_normal = imgui.io.addFontFromFile(assets.fonts.roboto_medium.path, font_size);
    imgui.io.setDefaultFont(font_normal);

    app.render_pipeline = app.core.device().createRenderPipeline(&pipeline_descriptor);
    app.queue = app.core.device().getQueue();

    app.render_bind_group = app.core.device().createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = app.render_pipeline.getBindGroupLayout(0), // group 0
        .entries = &.{
            gpu.BindGroup.Entry.textureView(0, app.texture.createView(&gpu.TextureView.Descriptor{})),
        },
    }));
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

    app.raytracing_shader.deinit();
    app.render_shader.deinit();

    imgui.mach_backend.deinit();
    imgui.deinit();
}

pub fn update(app: *App) !bool {
    app.time.delta_time = app.timer.lap();
    app.time.time += app.time.delta_time;

    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            else => {},
        }
        if (!app.input_data.mouse_captured) {
            // Don't allow interaction with Imgui widgets while the mouse is captured
            imgui.mach_backend.passEvent(event);
        }
        input.processEvent(app, event);
    }

    if (app.input_data.pressed_keys.areKeysPressed()) {
        app.camera.calculateMovement(app.input_data.pressed_keys, app.time.delta_time);
    }

    try updateShaders(app);
    updateRaytracingData(app);
    updateUniforms(app);

    const back_buffer_view = app.core.swapChain().getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = app.core.device().createCommandEncoder(null);

    {
        // Raytracing pass
        const pass = encoder.beginComputePass(null);
        pass.setPipeline(app.raytracing_pipeline);
        pass.setBindGroup(0, app.raytracing_bind_group, null);
        pass.dispatchWorkgroups(app.game_config.screen_width / app.game_config.workgroup_size, app.game_config.screen_height / app.game_config.workgroup_size, 1);
        pass.end();
        pass.release();
    }

    {
        // Render pass
        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
        });
        const pass = encoder.beginRenderPass(&render_pass_info);
        pass.setPipeline(app.render_pipeline);
        pass.setBindGroup(0, app.render_bind_group, null);
        pass.draw(6, 1, 0, 0);

        // Imgui
        imgui.mach_backend.newFrame();

        ui.draw(app);

        imgui.mach_backend.draw(pass);

        pass.end();
        pass.release();
    }

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    app.core.swapChain().present();
    back_buffer_view.release();

    return false;
}

//////////////////////////////////////////////////////////////////////////////////////
// Internal
//////////////////////////////////////////////////////////////////////////////////////

fn createRaytracingPipeline(app: *App) !void {
    const raytracing_module = app.core.device().createShaderModuleWGSL(
        assets.shaders.raytrace,
        app.raytracing_shader.data(),
    );

    defer raytracing_module.release();

    app.raytracing_pipeline = app.core.device().createComputePipeline(
        &gpu.ComputePipeline.Descriptor{
            .compute = gpu.ProgrammableStageDescriptor{
                .module = raytracing_module,
                .entry_point = "main",
            },
        },
    );

    // Raytracing bind group
    app.raytracing_bind_group = app.core.device().createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = app.raytracing_pipeline.getBindGroupLayout(0), // group 0
        .entries = &.{
            gpu.BindGroup.Entry.buffer(0, app.voxel_grid_buffer, 0, app.voxel_grid_buffer.getSize()),
            gpu.BindGroup.Entry.textureView(1, app.texture.createView(&gpu.TextureView.Descriptor{})),
            gpu.BindGroup.Entry.buffer(2, app.raytracing_data_buffer, 0, @sizeOf(RaytracingData)),
        },
    }));
}

fn updateRaytracingData(app: *App) void {
    app.raytracing_data.dim = app.game_config.voxel_grid_dim;
    app.raytracing_data.camera_matrix = app.camera.matrices.view;
    app.raytracing_data.inverse_projection_matrix = app.camera.matrices.perspective;
}

fn updateShaders(app: *App) !void {
    try app.raytracing_shader.update();
    try app.render_shader.update();

    if (app.raytracing_shader.dirty) {
        try createRaytracingPipeline(app);
        app.raytracing_shader.dirty = false;
    }
}

fn updateUniforms(app: *App) void {
    const bytes = std.mem.toBytes(app.raytracing_data);
    app.queue.writeBuffer(app.raytracing_data_buffer, 0, bytes[0..]);
}

fn setupCamera(app: *App) void {
    app.camera = Camera{
        .rotation_speed = 0.5,
        .movement_speed = 10.0,
    };
    const aspect_ratio: f32 = @intToFloat(f32, app.core.descriptor().width) / @intToFloat(f32, app.core.descriptor().height);
    app.camera.position = .{ -10.0, -6.0, -6.0, 0.0 };
    app.camera.target = .{ 5.0, 5.0, -5.0, 0.0 };
    app.camera.setPerspective(90.0, aspect_ratio, 0.1, 1000.0);
    app.camera.updateTarget();
}
