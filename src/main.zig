// A simple FlappyBird-style game built with Zig v0.14 targeting WebAssembly to be used as a template.

const std = @import("std");
const game_mod = @import("game.zig");
const entities = @import("entities.zig");
const renderer = @import("renderer.zig");
const audio = @import("audio.zig");

// WASM imports for browser interaction
extern "env" fn consoleLog(ptr: [*]const u8, len: usize) void;

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
