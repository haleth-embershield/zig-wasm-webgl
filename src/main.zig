// A simple FlappyBird-style game built with Zig v0.14 targeting WebAssembly to be used as a template.

const std = @import("std");
const game_mod = @import("game.zig");
const entities = @import("entities.zig");
const renderer = @import("renderer.zig");
const audio = @import("audio.zig");

// WASM imports for browser interaction
extern "env" fn consoleLog(ptr: [*]const u8, len: usize) void;

// Game constants
const GRAVITY: f32 = 1000.0;
const JUMP_VELOCITY: f32 = -400.0;
const BIRD_SIZE: f32 = 30.0;
const PIPE_WIDTH: f32 = 120.0;
const PIPE_GAP: f32 = 200.0;
const PIPE_SPEED: f32 = 200.0;
const PIPE_SPAWN_INTERVAL: f32 = 2;

// Game dimensions
const GAME_WIDTH: usize = 800;
const GAME_HEIGHT: usize = 600;

// Game state enum
const GameState = enum {
    Menu,
    Playing,
    Paused,
    GameOver,
};

// Bird structure
const Bird = struct {
    x: f32,
    y: f32,
    velocity: f32,
    rotation: f32,

    fn init(x: f32, y: f32) Bird {
        return Bird{
            .x = x,
            .y = y,
            .velocity = 0,
            .rotation = 0,
        };
    }

    fn update(self: *Bird, delta_time: f32) void {
        // Apply gravity
        self.velocity += GRAVITY * delta_time;

        // Update position
        self.y += self.velocity * delta_time;

        // Clamp position to prevent going out of bounds
        self.y = std.math.clamp(self.y, BIRD_SIZE / 2, GAME_HEIGHT - BIRD_SIZE / 2);

        // Update rotation based on velocity
        self.rotation = std.math.clamp(self.velocity * 0.1, -45.0, 45.0);
    }

    fn jump(self: *Bird) void {
        self.velocity = JUMP_VELOCITY;
    }
};

// Pipe structure
const Pipe = struct {
    x: f32,
    gap_y: f32,
    active: bool,
    passed: bool,

    fn init(x: f32, gap_y: f32) Pipe {
        return Pipe{
            .x = x,
            .gap_y = gap_y,
            .active = true,
            .passed = false,
        };
    }

    fn update(self: *Pipe, delta_time: f32) void {
        if (!self.active) return;

        // Move pipe to the left
        self.x -= PIPE_SPEED * delta_time;

        // Deactivate if completely off screen (including the cap width)
        if (self.x < -(PIPE_WIDTH + 20)) {
            self.active = false;
        }
    }
};

// Game data structure
const GameData = struct {
    state: GameState,
    bird: Bird,
    pipes: [10]Pipe,
    pipe_count: usize,
    spawn_timer: f32,
    score: u32,
    high_score: u32,
    random_seed: u32,
    // Rendering resources
    game_image: renderer.Image,
    command_buffer: renderer.CommandBuffer,
    // Performance optimization timers
    menu_render_timer: f32,
    pause_render_timer: f32,
    gameover_render_timer: f32,

    fn init(alloc: std.mem.Allocator) !GameData {
        // Create game image buffer
        const game_image = try renderer.Image.init(alloc, GAME_WIDTH, GAME_HEIGHT, 3);

        // Initialize command buffer for batched WebGL calls
        const command_buffer = try renderer.CommandBuffer.init(alloc, 10); // Capacity for 10 commands

        // Create a properly initialized game data structure
        var game_data = GameData{
            .state = GameState.Menu,
            .bird = Bird.init(GAME_WIDTH / 4, GAME_HEIGHT / 2),
            .pipes = undefined, // Will be initialized below
            .pipe_count = 0,
            .spawn_timer = 0,
            .score = 0,
            .high_score = 0,
            .random_seed = 12345,
            .game_image = game_image,
            .command_buffer = command_buffer,
            .menu_render_timer = 0,
            .pause_render_timer = 0,
            .gameover_render_timer = 0,
        };

        // Initialize all pipes as inactive
        for (0..game_data.pipes.len) |i| {
            game_data.pipes[i] = Pipe{
                .x = 0,
                .gap_y = 0,
                .active = false,
                .passed = false,
            };
        }

        return game_data;
    }

    // Simple random number generator
    fn random(self: *GameData) u32 {
        self.random_seed = self.random_seed *% 1664525 +% 1013904223;
        return self.random_seed;
    }

    // Get random value in range [min, max)
    fn randomInRange(self: *GameData, min: u32, max: u32) u32 {
        return min + (self.random() % (max - min));
    }

    fn reset(self: *GameData) void {
        // Update high score if needed
        if (self.score > self.high_score) {
            self.high_score = self.score;
        }

        // Reset game state with bird in a safe position
        const safe_x = GAME_WIDTH / 4;
        const safe_y = GAME_HEIGHT / 2;
        self.bird = Bird.init(safe_x, safe_y);

        // Clear all existing pipes
        for (0..self.pipe_count) |i| {
            self.pipes[i].active = false;
        }
        self.pipe_count = 0;

        self.spawn_timer = 0;
        self.score = 0;
        self.state = GameState.Playing;

        // Reset render timers
        self.menu_render_timer = 0;
        self.pause_render_timer = 0;
        self.gameover_render_timer = 0;
    }

    fn addPipe(self: *GameData) void {
        if (self.pipe_count >= self.pipes.len) return;

        // Random gap position between 150 and canvas_height - 150
        const min_gap_y: u32 = 150;
        const max_gap_y: u32 = @intCast(GAME_HEIGHT - 150);
        const gap_y = @as(f32, @floatFromInt(self.randomInRange(min_gap_y, max_gap_y)));

        self.pipes[self.pipe_count] = Pipe.init(GAME_WIDTH, gap_y);
        self.pipe_count += 1;
    }

    fn deinit(self: *GameData, alloc: std.mem.Allocator) void {
        // Free allocated resources
        self.game_image.deinit(alloc);
        self.command_buffer.deinit(alloc);
    }
};

// Global state
var allocator: std.mem.Allocator = undefined;
var game: game_mod.Game = undefined;

// Helper to log strings to browser console
fn logString(msg: []const u8) void {
    consoleLog(msg.ptr, msg.len);
}

// Initialize the WASM module
export fn init() void {
    // Initialize allocator
    allocator = std.heap.page_allocator;

    // Initialize game data
    game = game_mod.Game.init(allocator) catch {
        logString("Failed to initialize game");
        return;
    };

    logString("FlappyBird initialized");
}

// Start or reset the game
export fn resetGame() void {
    game.reset();
    logString("Game reset");
}

// Update animation frame
export fn update(delta_time: f32) void {
    game.update(delta_time);
    game.render();
}

// Handle jump (spacebar or click)
export fn handleJump() void {
    game.handleJump();
}

// Handle mouse click
export fn handleClick(x_pos: f32, y_pos: f32) void {
    _ = x_pos;
    _ = y_pos;
    // Just call handleJump for any click
    handleJump();
}

// Toggle pause state
export fn togglePause() void {
    game.togglePause();
    logString("Game pause toggled");
}

// Clean up resources when the module is unloaded
export fn deinit() void {
    game.deinit(allocator);
    logString("Game resources freed");
}
