const assets = @import("assets");
const std = @import("std");
const mach = @import("mach");
const imgui = @import("imgui").MachImgui(mach);
const gpu = mach.gpu;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const GameConfig = struct { screen_width: u32 = 1920, screen_height: u32 = 1080 };

core: mach.Core,
game_config: GameConfig,
compute_pipeline: *gpu.ComputePipeline,
render_pipeline: *gpu.RenderPipeline,
imgui_pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,

pub fn init(app: *App) !void {
    app.game_config = GameConfig{};

    try app.core.init(gpa.allocator(), .{ .title = "Zoxel", .size = .{
        .width = app.game_config.screen_width,
        .height = app.game_config.screen_height,
    } });

    // Render pipeline
    const shader_module = app.core.device().createShaderModuleWGSL("triangle.wgsl", @embedFile("shaders/triangle.wgsl"));
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

    // Imgui pipeline
    const imgui_shader_module = app.core.device().createShaderModuleWGSL("imgui.wgsl", @embedFile("shaders/imgui.wgsl"));
    const imgui_fragment = gpu.FragmentState.init(.{
        .module = imgui_shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });
    const imgui_pipeline_descriptor = gpu.RenderPipeline.Descriptor{ .fragment = &imgui_fragment, .vertex = gpu.VertexState{
        .module = imgui_shader_module,
        .entry_point = "vert_main",
    } };

    imgui.init(gpa.allocator());
    imgui.mach_backend.init(&app.core, app.core.device(), app.core.descriptor().format, .{});

    const font_size = 18.0;
    const font_normal = imgui.io.addFontFromFile(assets.fonts.roboto_medium.path, font_size);
    imgui.io.setDefaultFont(font_normal);

    app.render_pipeline = app.core.device().createRenderPipeline(&pipeline_descriptor);
    app.imgui_pipeline = app.core.device().createRenderPipeline(&imgui_pipeline_descriptor);
    app.queue = app.core.device().getQueue();

    shader_module.release();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

    imgui.mach_backend.deinit();
}

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            else => {},
        }
        imgui.mach_backend.passEvent(event);
    }

    const back_buffer_view = app.core.swapChain().getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = app.core.device().createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    {}
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.render_pipeline);
    pass.draw(3, 1, 0, 0);

    pass.setPipeline(app.imgui_pipeline);

    imgui.mach_backend.newFrame();
    imgui_draw: {
        imgui.setNextWindowPos(.{ .x = 0, .y = 0 });
        if (!imgui.begin("Settings", .{})) {
            imgui.end();
            break :imgui_draw;
        }
        defer imgui.end();

        // Render imgui content
        imgui.text("{s}", .{"Test!"});
    }

    imgui.mach_backend.draw(pass);

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    app.core.swapChain().present();
    back_buffer_view.release();

    return false;
}
