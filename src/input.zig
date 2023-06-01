const mach = @import("mach");
const zmath = @import("zmath");
const App = @import("main.zig").App;
const prelude = @import("prelude.zig");

pub const PressedKeys = packed struct(u16) {
    right: bool = false,
    left: bool = false,
    forward: bool = false,
    backward: bool = false,
    up: bool = false,
    down: bool = false,
    padding: u10 = undefined,

    pub inline fn areKeysPressed(self: @This()) bool {
        return (self.forward or self.backward or self.left or self.right or self.up or self.down);
    }

    pub inline fn clear(self: *@This()) void {
        self.right = false;
        self.left = false;
        self.forward = false;
        self.backward = false;
    }
};

pub const InputData = struct {
    mouse_position: mach.Core.Position = .{
        .x = 0.0,
        .y = 0.0,
    },
    pressed_keys: PressedKeys = .{},
    mouse_captured: bool = false,
};

pub fn processEvent(app: *App, event: mach.Core.Event) void {
    switch (event) {
        .mouse_motion => |ev| {
            // Only affect the camera when the mouse is captured
            if (app.input_data.mouse_captured) {
                const delta = prelude.Vec2{
                    @floatCast(f32, (app.input_data.mouse_position.x - ev.pos.x) * app.camera.rotation_speed),
                    @floatCast(f32, (app.input_data.mouse_position.y - ev.pos.y) * app.camera.rotation_speed),
                };
                app.camera.rotate(delta);
            }

            app.input_data.mouse_position = ev.pos;
        },
        .mouse_press => |ev| {
            const button = ev.button;
            if (ev.mods.control and button == .left) {
                app.core.setCursorMode(.disabled);
                app.input_data.mouse_captured = true;
            }
        },
        .key_press, .key_repeat => |ev| {
            const key = ev.key;
            if (key == .up or key == .w) app.input_data.pressed_keys.forward = true;
            if (key == .down or key == .s) app.input_data.pressed_keys.backward = true;
            if (key == .left or key == .a) app.input_data.pressed_keys.left = true;
            if (key == .right or key == .d) app.input_data.pressed_keys.right = true;
            if (key == .space) app.input_data.pressed_keys.up = true;
            if (key == .left_shift) app.input_data.pressed_keys.down = true;

            if (key == .escape) {
                app.core.setCursorMode(.normal);
                app.input_data.mouse_captured = false;
            }
        },
        .key_release => |ev| {
            const key = ev.key;
            if (key == .up or key == .w) app.input_data.pressed_keys.forward = false;
            if (key == .down or key == .s) app.input_data.pressed_keys.backward = false;
            if (key == .left or key == .a) app.input_data.pressed_keys.left = false;
            if (key == .right or key == .d) app.input_data.pressed_keys.right = false;
            if (key == .space) app.input_data.pressed_keys.up = false;
            if (key == .left_shift) app.input_data.pressed_keys.down = false;
        },
        else => {},
    }
}
