// ASCII FlappyBird
// A simple FlappyBird-style game built with Zig v0.14 targeting WebAssembly

const std = @import("std");
const renderer = @import("renderer.zig");

// WASM imports for browser interaction
extern "env" fn consoleLog(ptr: [*]const u8, len: usize) void;
extern "env" fn clearCanvas() void;
extern "env" fn playJumpSound() void;
extern "env" fn playExplodeSound() void;
extern "env" fn playFailSound() void;

// Game constants
const GRAVITY: f32 = 1000.0;
const JUMP_VELOCITY: f32 = -400.0;
const BIRD_SIZE: f32 = 30.0;
const PIPE_WIDTH: f32 = 120.0;
const PIPE_GAP: f32 = 200.0;
const PIPE_SPEED: f32 = 200.0;
const PIPE_SPAWN_INTERVAL: f32 = 2;

// ASCII rendering constants
const ASCII_WIDTH: usize = 100; // Characters wide
const ASCII_HEIGHT: usize = 75; // Characters tall
const PIXEL_WIDTH: usize = ASCII_WIDTH * 8; // Each ASCII char is 8x8 pixels
const PIXEL_HEIGHT: usize = ASCII_HEIGHT * 8;

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
        self.y = std.math.clamp(self.y, BIRD_SIZE / 2, PIXEL_HEIGHT - BIRD_SIZE / 2);

        // Update rotation based on velocity
        self.rotation = std.math.clamp(self.velocity * 0.1, -45.0, 45.0);
    }

    fn jump(self: *Bird) void {
        self.velocity = JUMP_VELOCITY;
        playJumpSound();
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
    // ASCII rendering resources
    ascii_renderer: renderer.RenderParams,
    game_image: renderer.Image,
    ascii_output: []u8,
    // Command buffer for batched WebGL calls
    command_buffer: renderer.CommandBuffer,
    // Performance optimization timers
    menu_render_timer: f32,
    pause_render_timer: f32,
    gameover_render_timer: f32,

    fn init(alloc: std.mem.Allocator) !GameData {
        // Initialize ASCII renderer
        const ascii_renderer = try renderer.createRenderer(alloc);

        // Create game image buffer
        const game_image = try renderer.createImage(alloc, PIXEL_WIDTH, PIXEL_HEIGHT, 3);

        // Initialize with empty ASCII output - we'll use the preallocated buffer
        // const ascii_output = try alloc.alloc(u8, PIXEL_WIDTH * PIXEL_HEIGHT * 3);
        const ascii_output = &[_]u8{};

        // Initialize command buffer for batched WebGL calls
        const command_buffer = try renderer.CommandBuffer.init(alloc, 10); // Capacity for 10 commands

        // Create a properly initialized game data structure
        var game_data = GameData{
            .state = GameState.Menu,
            .bird = Bird.init(PIXEL_WIDTH / 4, PIXEL_HEIGHT / 2),
            .pipes = undefined, // Will be initialized below
            .pipe_count = 0,
            .spawn_timer = 0,
            .score = 0,
            .high_score = 0,
            .random_seed = 12345,
            .ascii_renderer = ascii_renderer,
            .game_image = game_image,
            .ascii_output = ascii_output,
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
        // Place bird in the middle of the screen, away from edges
        const safe_x = PIXEL_WIDTH / 4;
        const safe_y = PIXEL_HEIGHT / 2;
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
        const max_gap_y: u32 = @intCast(PIXEL_HEIGHT - 150);
        const gap_y = @as(f32, @floatFromInt(self.randomInRange(min_gap_y, max_gap_y)));

        self.pipes[self.pipe_count] = Pipe.init(PIXEL_WIDTH, gap_y);
        self.pipe_count += 1;
    }

    fn deinit(self: *GameData, alloc: std.mem.Allocator) void {
        // Free allocated resources
        self.ascii_renderer.deinit(alloc);
        renderer.destroyImage(alloc, self.game_image);

        // Free command buffer
        self.command_buffer.deinit(alloc);

        // We don't need to free ascii_output anymore as it points to the global buffer
        // which is freed separately in the main deinit function
        // alloc.free(self.ascii_output);
    }
};

// Global state
var allocator: std.mem.Allocator = undefined;
var game: GameData = undefined;

// Export the renderer params for use in renderer.zig
pub fn getRendererParams() renderer.RenderParams {
    // Ensure game is initialized
    if (@intFromPtr(&game) == 0) {
        // Return a default configuration if game is not initialized
        const default_chars = " .:-=+*#@%";
        const default_info = renderer.initAsciiChars(std.heap.wasm_allocator, default_chars) catch unreachable;
        return renderer.RenderParams{
            .ascii_chars = default_chars,
            .ascii_info = default_info,
            .color = true,
            .invert_color = false,
            .block_size = 4,
            .detect_edges = false,
            .sigma1 = 0.5,
            .sigma2 = 1.0,
            .brightness_boost = 1.5,
            .threshold_disabled = false,
            .dither = .None,
            .bg_color = null,
            .fg_color = null,
        };
    }
    return game.ascii_renderer;
}

// Helper to log strings to browser console
fn logString(msg: []const u8) void {
    consoleLog(msg.ptr, msg.len);
}

// Initialize the WASM module
export fn init() void {
    // Initialize allocator
    allocator = std.heap.page_allocator;

    // Initialize game data
    game = GameData.init(allocator) catch {
        logString("Failed to initialize game");
        return;
    };

    // Preallocate ASCII buffer to prevent per-frame allocations
    renderer.preallocateAsciiBuffer(allocator, PIXEL_WIDTH, PIXEL_HEIGHT) catch {
        logString("Failed to preallocate ASCII buffer");
        // Continue anyway, the renderer will fall back to per-frame allocations
    };

    // Ensure the bird starts in a safe position
    game.bird = Bird.init(PIXEL_WIDTH / 4, PIXEL_HEIGHT / 2);

    logString("ASCII FlappyBird initialized");
}

// Start or reset the game
export fn resetGame() void {
    game.reset();
    logString("Game reset");
}

// Update animation frame
export fn update(delta_time: f32) void {
    // Cap delta time to prevent large jumps
    const capped_delta = @min(delta_time, 0.05);

    if (game.state == GameState.Menu) {
        // Only redraw menu occasionally to save performance
        game.menu_render_timer += capped_delta;
        if (game.menu_render_timer >= 0.1) { // Redraw menu at 10 FPS
            game.menu_render_timer = 0;
            drawMenu();
        }
        return;
    }

    if (game.state == GameState.Playing) {
        // Update game logic only when playing
        updateGame(capped_delta);
        // Always draw the game for Playing state
        drawGame();
    } else if (game.state == GameState.GameOver) {
        // For game over, only redraw occasionally
        game.gameover_render_timer += capped_delta;
        if (game.gameover_render_timer >= 0.2) { // Redraw at 5 FPS
            game.gameover_render_timer = 0;
            drawGame();
        }
    } else if (game.state == GameState.Paused) {
        // For paused state, only redraw occasionally
        game.pause_render_timer += capped_delta;
        if (game.pause_render_timer >= 0.5) { // Redraw at 2 FPS
            game.pause_render_timer = 0;
            drawGame();
        }
    }
}

// Handle jump (spacebar or click)
export fn handleJump() void {
    if (game.state == GameState.Menu) {
        // Start game if in menu
        game.state = GameState.Playing;
        // Reset render timers
        game.menu_render_timer = 0;
        game.pause_render_timer = 0;
        game.gameover_render_timer = 0;
        // Ensure bird is in a safe position when starting
        game.bird = Bird.init(PIXEL_WIDTH / 4, PIXEL_HEIGHT / 2);
        return;
    }

    if (game.state == GameState.Paused) {
        // Resume game if paused
        game.state = GameState.Playing;
        // Reset render timers
        game.pause_render_timer = 0;
        return;
    }

    if (game.state == GameState.GameOver) {
        // Reset game if game over
        // Reset render timers
        game.gameover_render_timer = 0;
        resetGame();
        return;
    }

    // Make the bird jump
    game.bird.jump();
}

// Handle mouse click
export fn handleClick(x_pos: f32, y_pos: f32) void {
    _ = x_pos;
    _ = y_pos;
    // Just call handleJump for any click
    handleJump();
}

// Update game logic
fn updateGame(delta_time: f32) void {
    // Update bird
    game.bird.update(delta_time);

    // Check for collision with floor or ceiling
    const hit_ceiling = game.bird.y < BIRD_SIZE / 2; // Use bird radius for better bounds checking
    const hit_floor = game.bird.y > PIXEL_HEIGHT - BIRD_SIZE / 2;

    if (hit_ceiling or hit_floor) {
        gameOver();
        return;
    }

    // Update pipes and spawn new ones
    game.spawn_timer += delta_time;
    if (game.spawn_timer >= PIPE_SPAWN_INTERVAL) {
        game.spawn_timer = 0;
        game.addPipe();
    }

    var i: usize = 0;
    while (i < game.pipe_count) {
        var pipe = &game.pipes[i];
        pipe.update(delta_time);

        // Check for collision with pipe
        if (checkCollision(game.bird, pipe.*)) {
            gameOver();
            return;
        }

        // Check if bird passed the pipe
        if (!pipe.passed and game.bird.x > pipe.x + PIPE_WIDTH) {
            pipe.passed = true;
            game.score += 1;

            // Log score for debugging
            var score_buf: [32]u8 = undefined;
            const score_msg = std.fmt.bufPrint(&score_buf, "Score: {d}", .{game.score}) catch "Score updated";
            logString(score_msg);
        }

        // Remove inactive pipes
        if (!pipe.active) {
            game.pipes[i] = game.pipes[game.pipe_count - 1];
            game.pipe_count -= 1;
        } else {
            i += 1;
        }
    }
}

// Check collision between bird and pipe
fn checkCollision(bird: Bird, pipe: Pipe) bool {
    // Bird hitbox (simplified as a circle)
    const bird_radius = BIRD_SIZE / 2;

    // Check if bird is within pipe's x-range (including caps)
    const pipe_left = pipe.x - 10; // Account for cap extending to the left
    const pipe_right = pipe.x + PIPE_WIDTH + 10; // Account for cap extending to the right
    const bird_right = bird.x + bird_radius;
    const bird_left = bird.x - bird_radius;

    const is_within_x_range = bird_right > pipe_left and bird_left < pipe_right;

    if (is_within_x_range) {
        // Check if bird is outside the gap
        const bird_top = bird.y - bird_radius;
        const bird_bottom = bird.y + bird_radius;
        const gap_top = pipe.gap_y - PIPE_GAP / 2;
        const gap_bottom = pipe.gap_y + PIPE_GAP / 2;

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

// Game over
fn gameOver() void {
    if (game.state == GameState.GameOver) return; // Prevent multiple game over calls

    game.state = GameState.GameOver;
    playFailSound();
    logString("Game Over!");

    // Update high score if needed
    if (game.score > game.high_score) {
        game.high_score = game.score;

        var score_buf: [32]u8 = undefined;
        const high_score_msg = std.fmt.bufPrint(&score_buf, "New High Score: {d}", .{game.high_score}) catch "New High Score!";
        logString(high_score_msg);
    }
}

// Draw the game using ASCII renderer
fn drawGame() void {
    // Clear the image
    renderer.clearImage(game.game_image, .{ 0, 0, 0 }); // Black background

    // Draw ground
    renderer.drawRect(game.game_image, 0, PIXEL_HEIGHT - 50, PIXEL_WIDTH, 50, .{ 83, 54, 10 });

    // Draw grass
    renderer.drawRect(game.game_image, 0, PIXEL_HEIGHT - 50, PIXEL_WIDTH, 5, .{ 34, 139, 34 });

    // Draw pipes
    for (game.pipes[0..game.pipe_count]) |pipe| {
        if (!pipe.active) continue;

        // Skip pipes that are completely off-screen
        if (pipe.x + PIPE_WIDTH < 0) continue;

        // Draw pipe body
        const pipe_x: usize = @intFromFloat(@max(0, pipe.x));
        const pipe_width: usize = if (pipe.x < 0)
            @intFromFloat(@min(PIPE_WIDTH + pipe.x, PIPE_WIDTH)) // Adjust width for partially off-screen pipes
        else
            @intFromFloat(PIPE_WIDTH);
        const gap_y: usize = @intFromFloat(pipe.gap_y);
        const gap_half: usize = @intFromFloat(PIPE_GAP / 2);

        // Top pipe - use a much brighter green for better visibility in ASCII
        if (gap_y > gap_half) {
            // Draw a black border around the pipe first - with safe bounds checking
            const border_x = if (pipe_x >= 2) pipe_x - 2 else 0;
            const border_width = pipe_width + 4;
            renderer.drawRect(game.game_image, border_x, 0, border_width, gap_y - gap_half, .{ 0, 0, 0 });
            // Then draw the pipe itself
            renderer.drawRect(game.game_image, pipe_x, 0, pipe_width, gap_y - gap_half, .{ 0, 255, 0 });

            // Draw top pipe cap with even brighter color
            const cap_width = @min(pipe_width + 20, PIXEL_WIDTH - pipe_x); // Wider cap for better visibility, but don't exceed screen width
            const cap_x = if (pipe_x >= 10) pipe_x - 10 else 0;
            // Draw a black border around the cap - with safe bounds checking
            const cap_border_x = if (cap_x >= 2) cap_x - 2 else 0;
            const cap_border_width = @min(cap_width + 4, PIXEL_WIDTH - cap_border_x);
            const cap_y_pos = if (gap_y > gap_half + 17) gap_y - gap_half - 17 else 0;
            const cap_height = if (gap_y > gap_half + 17) 19 else gap_y - gap_half;
            renderer.drawRect(game.game_image, cap_border_x, cap_y_pos, cap_border_width, cap_height, .{ 0, 0, 0 });
            // Then draw the cap itself - with safe bounds checking
            const cap_inner_y_pos = if (gap_y > gap_half + 15) gap_y - gap_half - 15 else 0;
            const cap_inner_height = if (gap_y > gap_half + 15) 15 else gap_y - gap_half;
            renderer.drawRect(game.game_image, cap_x, cap_inner_y_pos, cap_width, cap_inner_height, .{ 50, 255, 50 });
        }

        // Bottom pipe - use a much brighter green for better visibility in ASCII
        if (gap_y + gap_half < PIXEL_HEIGHT) {
            // Draw a black border around the pipe first - with safe bounds checking
            const border_x = if (pipe_x >= 2) pipe_x - 2 else 0;
            const border_width = pipe_width + 4;
            renderer.drawRect(game.game_image, border_x, gap_y + gap_half, border_width, PIXEL_HEIGHT - (gap_y + gap_half), .{ 0, 0, 0 });
            // Then draw the pipe itself
            renderer.drawRect(game.game_image, pipe_x, gap_y + gap_half, pipe_width, PIXEL_HEIGHT - (gap_y + gap_half), .{ 0, 255, 0 });

            // Draw bottom pipe cap with even brighter color
            if (pipe_x > 10) {
                const cap_width = @min(pipe_width + 20, PIXEL_WIDTH - pipe_x); // Wider cap for better visibility, but don't exceed screen width
                const cap_x = if (pipe_x >= 10) pipe_x - 10 else 0;
                // Draw a black border around the cap - with safe bounds checking
                const cap_border_x = if (cap_x >= 2) cap_x - 2 else 0;
                const cap_border_width = @min(cap_width + 4, PIXEL_WIDTH - cap_border_x);
                // Make sure we don't exceed the image height
                const cap_border_height = @min(19, PIXEL_HEIGHT - (gap_y + gap_half));
                renderer.drawRect(game.game_image, cap_border_x, gap_y + gap_half, cap_border_width, cap_border_height, .{ 0, 0, 0 });
                // Then draw the cap itself
                const cap_height = @min(15, PIXEL_HEIGHT - (gap_y + gap_half));
                renderer.drawRect(game.game_image, cap_x, gap_y + gap_half, cap_width, cap_height, .{ 50, 255, 50 });
            }
        }
    }

    // Draw bird (with bounds checking)
    const bird_x: usize = @intFromFloat(@max(0, @min(game.bird.x, @as(f32, @floatFromInt(PIXEL_WIDTH - 1)))));
    const bird_y: usize = @intFromFloat(@max(0, @min(game.bird.y, @as(f32, @floatFromInt(PIXEL_HEIGHT - 1)))));
    const bird_radius: usize = @intFromFloat(BIRD_SIZE / 2);

    renderer.drawCircle(game.game_image, bird_x, bird_y, bird_radius, .{ 255, 255, 0 });

    // Draw score
    // Note: We can't directly draw text with the ASCII renderer
    // We'll display the score in the HTML UI instead

    // Check if ASCII rendering is enabled
    if (game.ascii_renderer.use_ascii) {
        // Render the game image to ASCII using the preallocated buffer
        game.ascii_output = renderer.renderToAscii(allocator, game.game_image, game.ascii_renderer) catch {
            logString("Failed to render ASCII");
            return;
        };

        // Render ASCII output to WebGL using batched commands
        renderer.render_game_frame_batched(&game.command_buffer, game.ascii_output.ptr, PIXEL_WIDTH, PIXEL_HEIGHT, 3);
    } else {
        // Render the original game image directly to WebGL using batched commands
        renderer.render_game_frame_batched(&game.command_buffer, game.game_image.data.ptr, PIXEL_WIDTH, PIXEL_HEIGHT, 3);
    }
}

// Draw menu screen
fn drawMenu() void {
    // Clear the image
    renderer.clearImage(game.game_image, .{ 0, 0, 0 }); // Black background

    // Draw ground
    renderer.drawRect(game.game_image, 0, PIXEL_HEIGHT - 50, PIXEL_WIDTH, 50, .{ 83, 54, 10 });

    // Draw grass
    renderer.drawRect(game.game_image, 0, PIXEL_HEIGHT - 50, PIXEL_WIDTH, 5, .{ 34, 139, 34 });

    // Draw a sample bird in the center
    renderer.drawCircle(game.game_image, PIXEL_WIDTH / 2, PIXEL_HEIGHT / 2, @intFromFloat(BIRD_SIZE / 2), .{ 255, 255, 0 });

    // Check if ASCII rendering is enabled
    if (game.ascii_renderer.use_ascii) {
        // Render the menu image to ASCII using the preallocated buffer
        game.ascii_output = renderer.renderToAscii(allocator, game.game_image, game.ascii_renderer) catch {
            logString("Failed to render ASCII menu");
            return;
        };

        // Render ASCII output to WebGL using batched commands
        renderer.render_game_frame_batched(&game.command_buffer, game.ascii_output.ptr, PIXEL_WIDTH, PIXEL_HEIGHT, 3);
    } else {
        // Render the original game image directly to WebGL using batched commands
        renderer.render_game_frame_batched(&game.command_buffer, game.game_image.data.ptr, PIXEL_WIDTH, PIXEL_HEIGHT, 3);
    }
}

// Toggle pause state
export fn togglePause() void {
    if (game.state == GameState.Playing) {
        game.state = GameState.Paused;
        // Reset pause render timer
        game.pause_render_timer = 0;
        logString("Game paused");
    } else if (game.state == GameState.Paused) {
        game.state = GameState.Playing;
        logString("Game resumed");
    }
}

// Toggle ASCII rendering on/off
export fn setUseAscii(use_ascii: bool) void {
    game.ascii_renderer.use_ascii = use_ascii;
    logString(if (use_ascii) "ASCII rendering enabled" else "ASCII rendering disabled");
}

// Change the ASCII character set
export fn setCharacterSet(set_index: u32) void {
    // Set the new character set based on the index
    const char_set = switch (set_index) {
        0 => renderer.DEFAULT_ASCII,
        1 => renderer.DEFAULT_BLOCK,
        2 => renderer.FULL_CHARACTERS,
        else => renderer.DEFAULT_ASCII,
    };

    // Initialize the new character info first
    const new_ascii_info = renderer.initAsciiChars(allocator, char_set) catch {
        logString("Failed to initialize character set");
        return;
    };

    // Free the old character info only after successful initialization
    allocator.free(game.ascii_renderer.ascii_info);
    game.ascii_renderer.ascii_chars = char_set;
    game.ascii_renderer.ascii_info = new_ascii_info;

    var msg_buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "Character set changed to index: {d}", .{set_index}) catch "Character set changed";
    logString(msg);
}

// Clean up resources when the module is unloaded
export fn deinit() void {
    // Free the preallocated ASCII buffer
    renderer.freeAsciiBuffer(allocator);

    // Clean up game resources
    game.deinit(allocator);
    logString("Game resources freed");
}
