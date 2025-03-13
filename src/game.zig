const std = @import("std");
const entities = @import("entities.zig");
const renderer = @import("renderer.zig");
const audio = @import("audio.zig");

// Game state enum
pub const GameState = enum {
    Menu,
    Playing,
    Paused,
    GameOver,
};

// Game data structure
pub const Game = struct {
    state: GameState,
    bird: entities.Bird,
    pipes: [10]entities.Pipe,
    pipe_count: usize,
    spawn_timer: f32,
    score: u32,
    high_score: u32,
    random_seed: u32,
    // Rendering resources
    renderer: renderer.Renderer,
    // Audio system
    audio_system: audio.AudioSystem,
    // Performance optimization timers
    menu_render_timer: f32,
    pause_render_timer: f32,
    gameover_render_timer: f32,

    pub fn init(alloc: std.mem.Allocator, width: usize, height: usize) !Game {
        // Initialize renderer
        const game_renderer = try renderer.Renderer.init(alloc, width, height);

        // Initialize audio system
        const audio_system = audio.AudioSystem.init();

        // Create a properly initialized game data structure
        var game = Game{
            .state = GameState.Menu,
            .bird = undefined, // Will be initialized below
            .pipes = undefined, // Will be initialized below
            .pipe_count = 0,
            .spawn_timer = 0,
            .score = 0,
            .high_score = 0,
            .random_seed = 12345,
            .renderer = game_renderer,
            .audio_system = audio_system,
            .menu_render_timer = 0,
            .pause_render_timer = 0,
            .gameover_render_timer = 0,
        };

        // Initialize bird
        game.bird = entities.Bird.init(entities.GAME_WIDTH / 4, entities.GAME_HEIGHT / 2, &game.audio_system);

        // Initialize all pipes as inactive
        for (0..game.pipes.len) |i| {
            game.pipes[i] = entities.Pipe{
                .x = 0,
                .gap_y = 0,
                .active = false,
                .passed = false,
            };
        }

        return game;
    }

    // Simple random number generator
    fn random(self: *Game) u32 {
        self.random_seed = self.random_seed *% 1664525 +% 1013904223;
        return self.random_seed;
    }

    // Get random value in range [min, max)
    fn randomInRange(self: *Game, min: u32, max: u32) u32 {
        return min + (self.random() % (max - min));
    }

    pub fn reset(self: *Game) void {
        // Update high score if needed
        if (self.score > self.high_score) {
            self.high_score = self.score;
        }

        // Reset game state with bird in a safe position
        const safe_x = entities.GAME_WIDTH / 4;
        const safe_y = entities.GAME_HEIGHT / 2;
        self.bird = entities.Bird.init(safe_x, safe_y, &self.audio_system);

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

    fn addPipe(self: *Game) void {
        if (self.pipe_count >= self.pipes.len) return;

        // Random gap position between 150 and canvas_height - 150
        const min_gap_y: u32 = 150;
        const max_gap_y: u32 = @intCast(entities.GAME_HEIGHT - 150);
        const gap_y = @as(f32, @floatFromInt(self.randomInRange(min_gap_y, max_gap_y)));

        self.pipes[self.pipe_count] = entities.Pipe.init(entities.GAME_WIDTH, gap_y);
        self.pipe_count += 1;
    }

    pub fn update(self: *Game, delta_time: f32) void {
        // Cap delta time to prevent large jumps
        const capped_delta = @min(delta_time, 0.05);

        if (self.state == GameState.Menu) {
            // Only redraw menu occasionally to save performance
            self.menu_render_timer += capped_delta;
            self.renderMenu();
            return;
        }

        if (self.state != GameState.Playing) {
            // Update timers for other states
            if (self.state == GameState.GameOver) {
                self.gameover_render_timer += capped_delta;
                if (self.gameover_render_timer >= 0.2) { // Redraw at 5 FPS
                    self.gameover_render_timer = 0;
                    self.renderGame();
                }
            } else if (self.state == GameState.Paused) {
                self.pause_render_timer += capped_delta;
                if (self.pause_render_timer >= 0.5) { // Redraw at 2 FPS
                    self.pause_render_timer = 0;
                    self.renderGame();
                }
            }
            return;
        }

        // Update bird
        self.bird.update(capped_delta);

        // Check for collision with floor or ceiling
        const hit_ceiling = self.bird.y < entities.BIRD_SIZE / 2;
        const hit_floor = self.bird.y > entities.GAME_HEIGHT - entities.BIRD_SIZE / 2;

        if (hit_ceiling or hit_floor) {
            self.gameOver();
            return;
        }

        // Update pipes and spawn new ones
        self.spawn_timer += capped_delta;
        if (self.spawn_timer >= entities.PIPE_SPAWN_INTERVAL) {
            self.spawn_timer = 0;
            self.addPipe();
        }

        var i: usize = 0;
        while (i < self.pipe_count) {
            var pipe = &self.pipes[i];
            pipe.update(capped_delta);

            // Check for collision with pipe
            if (pipe.checkCollision(self.bird)) {
                self.gameOver();
                return;
            }

            // Check if bird passed the pipe
            if (!pipe.passed and self.bird.x > pipe.x + entities.PIPE_WIDTH) {
                pipe.passed = true;
                self.score += 1;
            }

            // Remove inactive pipes
            if (!pipe.active) {
                self.pipes[i] = self.pipes[self.pipe_count - 1];
                self.pipe_count -= 1;
            } else {
                i += 1;
            }
        }

        // Render the current frame
        self.renderGame();
    }

    fn gameOver(self: *Game) void {
        if (self.state == GameState.GameOver) return;

        self.state = GameState.GameOver;
        self.audio_system.playSound(.Fail);

        // Update high score if needed
        if (self.score > self.high_score) {
            self.high_score = self.score;
        }
    }

    fn renderGame(self: *Game) void {
        // Clear the screen with sky blue
        self.renderer.beginFrame(.{ 135, 206, 235 });

        // Draw ground
        self.renderer.drawRect(0, entities.GAME_HEIGHT - 50, entities.GAME_WIDTH, 50, .{ 83, 54, 10 });

        // Draw grass
        self.renderer.drawRect(0, entities.GAME_HEIGHT - 50, entities.GAME_WIDTH, 5, .{ 34, 139, 34 });

        // Draw pipes
        for (self.pipes[0..self.pipe_count]) |*pipe| {
            pipe.render(&self.renderer);
        }

        // Draw bird
        self.bird.render(&self.renderer);

        // End frame
        self.renderer.endFrame();
    }

    fn renderMenu(self: *Game) void {
        if (self.menu_render_timer < 0.1) return; // Redraw menu at 10 FPS
        self.menu_render_timer = 0;

        // Clear the screen with sky blue
        self.renderer.beginFrame(.{ 135, 206, 235 });

        // Draw ground
        self.renderer.drawRect(0, entities.GAME_HEIGHT - 50, entities.GAME_WIDTH, 50, .{ 83, 54, 10 });

        // Draw grass
        self.renderer.drawRect(0, entities.GAME_HEIGHT - 50, entities.GAME_WIDTH, 5, .{ 34, 139, 34 });

        // Draw a sample bird in the center
        self.renderer.drawCircle(entities.GAME_WIDTH / 2, entities.GAME_HEIGHT / 2, @intFromFloat(entities.BIRD_SIZE / 2), .{ 255, 255, 0 });

        // End frame
        self.renderer.endFrame();
    }

    pub fn handleJump(self: *Game) void {
        if (self.state == GameState.Menu) {
            // Start game if in menu
            self.state = GameState.Playing;
            // Reset render timers
            self.menu_render_timer = 0;
            self.pause_render_timer = 0;
            self.gameover_render_timer = 0;
            // Ensure bird is in a safe position when starting
            self.bird = entities.Bird.init(entities.GAME_WIDTH / 4, entities.GAME_HEIGHT / 2, &self.audio_system);
            return;
        }

        if (self.state == GameState.Paused) {
            // Resume game if paused
            self.state = GameState.Playing;
            // Reset render timers
            self.pause_render_timer = 0;
            return;
        }

        if (self.state == GameState.GameOver) {
            // Reset game if game over
            // Reset render timers
            self.gameover_render_timer = 0;
            self.reset();
            return;
        }

        // Make the bird jump
        self.bird.jump();
    }

    pub fn togglePause(self: *Game) void {
        if (self.state == GameState.Playing) {
            self.state = GameState.Paused;
            self.pause_render_timer = 0;
        } else if (self.state == GameState.Paused) {
            self.state = GameState.Playing;
        }
    }

    pub fn deinit(self: *Game, alloc: std.mem.Allocator) void {
        self.renderer.deinit(alloc);
    }
};
