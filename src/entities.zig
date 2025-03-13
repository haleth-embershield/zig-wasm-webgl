const std = @import("std");
const renderer = @import("renderer.zig");
const audio = @import("audio.zig");

// Game constants
pub const GRAVITY: f32 = 1000.0;
pub const JUMP_VELOCITY: f32 = -400.0;
pub const BIRD_SIZE: f32 = 30.0;
pub const PIPE_WIDTH: f32 = 120.0;
pub const PIPE_GAP: f32 = 200.0;
pub const PIPE_SPEED: f32 = 200.0;
pub const PIPE_SPAWN_INTERVAL: f32 = 2;

// Game dimensions
pub const GAME_WIDTH: usize = 800;
pub const GAME_HEIGHT: usize = 600;

// Bird entity
pub const Bird = struct {
    x: f32,
    y: f32,
    velocity: f32,
    rotation: f32,
    audio_system: *audio.AudioSystem,

    pub fn init(x: f32, y: f32, audio_system: *audio.AudioSystem) Bird {
        return Bird{
            .x = x,
            .y = y,
            .velocity = 0,
            .rotation = 0,
            .audio_system = audio_system,
        };
    }

    pub fn update(self: *Bird, delta_time: f32) void {
        // Apply gravity
        self.velocity += GRAVITY * delta_time;

        // Update position
        self.y += self.velocity * delta_time;

        // Clamp position to prevent going out of bounds
        self.y = std.math.clamp(self.y, BIRD_SIZE / 2, GAME_HEIGHT - BIRD_SIZE / 2);

        // Update rotation based on velocity
        self.rotation = std.math.clamp(self.velocity * 0.1, -45.0, 45.0);
    }

    pub fn jump(self: *Bird) void {
        self.velocity = JUMP_VELOCITY;
        self.audio_system.playSound(.Jump);
    }

    pub fn render(self: Bird, img: *renderer.Image) void {
        const bird_x: usize = @intFromFloat(@max(0, @min(self.x, @as(f32, @floatFromInt(GAME_WIDTH - 1)))));
        const bird_y: usize = @intFromFloat(@max(0, @min(self.y, @as(f32, @floatFromInt(GAME_HEIGHT - 1)))));
        const bird_radius: usize = @intFromFloat(BIRD_SIZE / 2);

        renderer.drawCircle(img.*, bird_x, bird_y, bird_radius, .{ 255, 255, 0 });
    }

    pub fn renderWithRenderer(self: Bird, renderer_obj: *renderer.Renderer, img: *renderer.Image) void {
        const bird_x: usize = @intFromFloat(@max(0, @min(self.x, @as(f32, @floatFromInt(GAME_WIDTH - 1)))));
        const bird_y: usize = @intFromFloat(@max(0, @min(self.y, @as(f32, @floatFromInt(GAME_HEIGHT - 1)))));
        const bird_radius: usize = @intFromFloat(BIRD_SIZE / 2);

        renderer_obj.renderCircle(img, bird_x, bird_y, bird_radius, .{ 255, 255, 0 });
    }
};

// Pipe entity
pub const Pipe = struct {
    x: f32,
    gap_y: f32,
    active: bool,
    passed: bool,

    pub fn init(x: f32, gap_y: f32) Pipe {
        return Pipe{
            .x = x,
            .gap_y = gap_y,
            .active = true,
            .passed = false,
        };
    }

    pub fn update(self: *Pipe, delta_time: f32) void {
        if (!self.active) return;

        // Move pipe to the left
        self.x -= PIPE_SPEED * delta_time;

        // Deactivate if completely off screen (including the cap width)
        if (self.x < -(PIPE_WIDTH + 20)) {
            self.active = false;
        }
    }

    pub fn render(self: Pipe, img: *renderer.Image) void {
        if (!self.active) return;

        // Skip pipes that are completely off-screen
        if (self.x + PIPE_WIDTH < 0) return;

        // Draw pipe body
        const pipe_x: usize = @intFromFloat(@max(0, self.x));
        const pipe_width: usize = if (self.x < 0)
            @intFromFloat(@min(PIPE_WIDTH + self.x, PIPE_WIDTH))
        else
            @intFromFloat(PIPE_WIDTH);
        const gap_y: usize = @intFromFloat(self.gap_y);
        const gap_half: usize = @intFromFloat(PIPE_GAP / 2);

        // Top pipe
        if (gap_y > gap_half) {
            renderer.drawRect(img.*, pipe_x, 0, pipe_width, gap_y - gap_half, .{ 0, 255, 0 });
            // Draw pipe cap
            const cap_width = @min(pipe_width + 20, GAME_WIDTH - pipe_x);
            const cap_x = if (pipe_x >= 10) pipe_x - 10 else 0;
            if (gap_y > gap_half + 15) {
                renderer.drawRect(img.*, cap_x, gap_y - gap_half - 15, cap_width, 15, .{ 50, 255, 50 });
            }
        }

        // Bottom pipe
        if (gap_y + gap_half < GAME_HEIGHT) {
            renderer.drawRect(img.*, pipe_x, gap_y + gap_half, pipe_width, GAME_HEIGHT - (gap_y + gap_half), .{ 0, 255, 0 });
            // Draw pipe cap
            if (pipe_x > 10) {
                const cap_width = @min(pipe_width + 20, GAME_WIDTH - pipe_x);
                const cap_x = if (pipe_x >= 10) pipe_x - 10 else 0;
                const cap_height = @min(15, GAME_HEIGHT - (gap_y + gap_half));
                renderer.drawRect(img.*, cap_x, gap_y + gap_half, cap_width, cap_height, .{ 50, 255, 50 });
            }
        }
    }

    pub fn renderWithRenderer(self: Pipe, renderer_obj: *renderer.Renderer, img: *renderer.Image) void {
        if (!self.active) return;

        // Skip pipes that are completely off-screen
        if (self.x + PIPE_WIDTH < 0) return;

        // Draw pipe body
        const pipe_x: usize = @intFromFloat(@max(0, self.x));
        const pipe_width: usize = if (self.x < 0)
            @intFromFloat(@min(PIPE_WIDTH + self.x, PIPE_WIDTH))
        else
            @intFromFloat(PIPE_WIDTH);
        const gap_y: usize = @intFromFloat(self.gap_y);
        const gap_half: usize = @intFromFloat(PIPE_GAP / 2);

        // Top pipe
        if (gap_y > gap_half) {
            renderer_obj.renderRect(img, pipe_x, 0, pipe_width, gap_y - gap_half, .{ 0, 255, 0 });
            // Draw pipe cap
            const cap_width = @min(pipe_width + 20, GAME_WIDTH - pipe_x);
            const cap_x = if (pipe_x >= 10) pipe_x - 10 else 0;
            if (gap_y > gap_half + 15) {
                renderer_obj.renderRect(img, cap_x, gap_y - gap_half - 15, cap_width, 15, .{ 50, 255, 50 });
            }
        }

        // Bottom pipe
        if (gap_y + gap_half < GAME_HEIGHT) {
            renderer_obj.renderRect(img, pipe_x, gap_y + gap_half, pipe_width, GAME_HEIGHT - (gap_y + gap_half), .{ 0, 255, 0 });
            // Draw pipe cap
            if (pipe_x > 10) {
                const cap_width = @min(pipe_width + 20, GAME_WIDTH - pipe_x);
                const cap_x = if (pipe_x >= 10) pipe_x - 10 else 0;
                const cap_height = @min(15, GAME_HEIGHT - (gap_y + gap_half));
                renderer_obj.renderRect(img, cap_x, gap_y + gap_half, cap_width, cap_height, .{ 50, 255, 50 });
            }
        }
    }

    // Check collision between bird and pipe
    pub fn checkCollision(self: Pipe, bird: Bird) bool {
        // Bird hitbox (simplified as a circle)
        const bird_radius = BIRD_SIZE / 2;

        // Check if bird is within pipe's x-range (including caps)
        const pipe_left = self.x - 10;
        const pipe_right = self.x + PIPE_WIDTH + 10;
        const bird_right = bird.x + bird_radius;
        const bird_left = bird.x - bird_radius;

        const is_within_x_range = bird_right > pipe_left and bird_left < pipe_right;

        if (is_within_x_range) {
            // Check if bird is outside the gap
            const bird_top = bird.y - bird_radius;
            const bird_bottom = bird.y + bird_radius;
            const gap_top = self.gap_y - PIPE_GAP / 2;
            const gap_bottom = self.gap_y + PIPE_GAP / 2;

            // Check for collision with pipe body
            const is_above_gap = bird_top < gap_top;
            const is_below_gap = bird_bottom > gap_bottom;

            // Check for collision with pipe caps
            const is_at_gap_edge_top = bird_bottom > gap_top - 15 and bird_top < gap_top;
            const is_at_gap_edge_bottom = bird_top < gap_bottom + 15 and bird_bottom > gap_bottom;

            if (is_above_gap or is_below_gap or (is_at_gap_edge_top and bird_right > pipe_left) or (is_at_gap_edge_bottom and bird_right > pipe_left)) {
                return true;
            }
        }

        return false;
    }
};
