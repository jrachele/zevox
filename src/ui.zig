const mach = @import("mach");
const imgui = @import("imgui.zig");
const App = @import("main.zig");
const Camera = @import("camera.zig").Camera;

pub fn draw(app: *App) void {
    imgui.setNextWindowPos(.{ .x = 0, .y = 0 });
    if (!imgui.begin("Settings", .{})) {
        imgui.end();
        return;
    }
    defer imgui.end();

    // Render imgui content
    imgui.text("ms: {d:.3}", .{app.time.delta_time * 1000});
    imgui.text("fps: {d:.3}", .{1.0 / app.time.delta_time});

    if (imgui.collapsingHeader("Camera Settings", .{})) {
        const position = app.camera.position;
        const forward = app.camera.target;
        imgui.text("pos x: {d:.3} y: {d:.3} z: {d:.3}", .{ position[0], position[1], position[2] });
        imgui.text("fwd x: {d:.3} y: {d:.3} z: {d:.3}", .{ forward[0], forward[1], forward[2] });

        _ = imgui.sliderFloat("Move speed", .{
            .v = &app.camera.movement_speed,
            .min = 0.0,
            .max = 100.0,
        });

        _ = imgui.sliderFloat("Sensitivity", .{
            .v = &app.camera.rotation_speed,
            .min = 0.0,
            .max = 10.0,
        });

        if (imgui.sliderFloat("FOV", .{
            .v = &app.camera.fov,
            .min = 60.0,
            .max = 120.0,
        })) {
            app.camera.updatePerspectiveMatrix();
        }

        if (imgui.sliderFloat("Near", .{
            .v = &app.camera.znear,
            .min = 0.05,
            .max = 3.0,
        })) {
            app.camera.updatePerspectiveMatrix();
        }

        if (imgui.sliderFloat("Far", .{
            .v = &app.camera.zfar,
            .min = 100.0,
            .max = 10000.0,
        })) {
            app.camera.updatePerspectiveMatrix();
        }
    }
}
