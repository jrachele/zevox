const std = @import("std");
const mach = @import("mach");
const math = std.math;
const zmath = @import("zmath");

const Mat4 = @import("prelude.zig").Mat4;
const Vec4 = @import("prelude.zig").Vec4;
const Vec3 = @import("prelude.zig").Vec3;
const Vec2 = @import("prelude.zig").Vec2;
const PressedKeys = @import("input.zig").PressedKeys;

// From mach pbr example
pub const Camera = struct {
    const Matrices = struct {
        perspective: Mat4 = [1]f32{0.0} ** 16,
        view: Mat4 = [1]f32{0.0} ** 16,
    };

    const YawAxis: Vec3 = .{ 0.0, 1.0, 0.0 };
    const PitchAxis: Vec3 = .{ 1.0, 0.0, 0.0 };

    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    target: Vec4 = .{ 0.0, 0.0, 0.0, 1.0 },
    position: Vec4 = .{ 0.0, 0.0, 0.0, 0.0 },

    aspect: f32 = 0.0,
    fov: f32 = 0.0,
    znear: f32 = 0.0,
    zfar: f32 = 0.0,

    rotation_speed: f32 = 0.0,
    movement_speed: f32 = 0.0,

    matrices: Matrices = .{},

    pub fn calculateMovement(self: *@This(), pressed_keys: PressedKeys, delta_time: f32) void {
        std.debug.assert(pressed_keys.areKeysPressed());
        var camera_front = self.target;
        var camera_right = zmath.normalize3(zmath.cross3(.{ 0.0, 1.0, 0.0, 0.0 }, camera_front));

        camera_front[0] *= self.movement_speed * delta_time;
        camera_front[1] *= self.movement_speed * delta_time;
        camera_front[2] *= self.movement_speed * delta_time;

        camera_right[0] *= self.movement_speed * delta_time;
        camera_right[1] *= self.movement_speed * delta_time;
        camera_right[2] *= self.movement_speed * delta_time;

        if (pressed_keys.forward) {
            self.position[0] += camera_front[0];
            self.position[1] += camera_front[1];
            self.position[2] += camera_front[2];
        }
        if (pressed_keys.backward) {
            self.position[0] -= camera_front[0];
            self.position[1] -= camera_front[1];
            self.position[2] -= camera_front[2];
        }
        if (pressed_keys.right) {
            self.position[0] -= camera_right[0];
            self.position[1] -= camera_right[1];
            self.position[2] -= camera_right[2];
        }
        if (pressed_keys.left) {
            self.position[0] += camera_right[0];
            self.position[1] += camera_right[1];
            self.position[2] += camera_right[2];
        }

        if (pressed_keys.up) {
            self.position[1] += self.movement_speed * delta_time;
        }
        if (pressed_keys.down) {
            self.position[1] -= self.movement_speed * delta_time;
        }
        self.updateViewMatrix();
    }

    fn updateViewMatrix(self: *@This()) void {
        var focusPos = self.position;
        focusPos[0] += self.target[0];
        focusPos[1] += self.target[1];
        focusPos[2] += self.target[2];
        // We want the inverse of the view matrix since we are projecting rays entirely in world space
        self.matrices.view = zmath.matToArr(zmath.inverse(zmath.lookAtRh(self.position, focusPos, [4]f32{ 0.0, 1.0, 0.0, 0.0 })));
    }

    pub fn updatePerspectiveMatrix(self: *@This()) void {
        const perspective = zmath.inverse(zmath.perspectiveFovRhGl(math.degreesToRadians(f32, self.fov), self.aspect, self.znear, self.zfar));
        self.matrices.perspective = zmath.matToArr(perspective);
    }

    pub fn setPerspective(self: *@This(), fov: f32, aspect: f32, znear: f32, zfar: f32) void {
        self.fov = fov;
        self.znear = znear;
        self.zfar = zfar;
        self.aspect = aspect;

        self.updatePerspectiveMatrix();
    }

    pub fn rotate(self: *@This(), delta: Vec2) void {
        self.yaw += delta[0] * self.rotation_speed;
        self.pitch += delta[1] * self.rotation_speed;

        self.pitch = zmath.clamp(self.pitch, -89.0, 89.0);

        self.updateTarget();
    }

    pub fn updateTarget(self: *@This()) void {
        const yaw = math.degreesToRadians(f32, self.yaw);
        const pitch = math.degreesToRadians(f32, self.pitch);
        self.target[0] = -math.sin(yaw) * math.cos(pitch);
        self.target[1] = math.sin(pitch);
        self.target[2] = -math.cos(yaw) * math.cos(pitch);
        self.updateViewMatrix();
    }
};
