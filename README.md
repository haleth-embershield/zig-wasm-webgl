# Zig-WASM-WebGL Game Template

A modern, high-performance game development template using Zig, WebAssembly, and WebGL. This template provides a solid foundation for building browser-based games with excellent performance characteristics and memory safety.

## Features

- **WebAssembly Integration**: Compile Zig code to WebAssembly for near-native performance in the browser
- **WebGL Rendering**: Clean, efficient hardware-accelerated graphics with a command buffer system
- **Memory-Safe Architecture**: Leverages Zig's memory safety features for robust game development
- **Optimized Build Pipeline**: Streamlined build process with development server included
- **Cross-Platform**: Works on any modern browser that supports WebAssembly and WebGL
- **Responsive Design**: Adapts to different screen sizes and device capabilities
- **Minimal JS-WASM Boundary**: Optimized communication between JavaScript and WebAssembly

## Getting Started

### Prerequisites

- Zig 0.14.0 or later

### Building and Running

```bash
# Build and run the project (starts a local web server)
zig build run

# Just build and deploy without running the server
zig build deploy

# Alternative: After deploying, serve with Python's HTTP server
zig build deploy
cd dist
python -m http.server
```

## Project Structure

```
src/
  ├── main.zig       (WASM exports and initialization)
  ├── game.zig       (Game state and logic)
  ├── entities.zig   (Game objects like Bird and Pipe)
  ├── renderer.zig   (WebGL rendering system)
  ├── audio.zig      (Audio system)
  └── assets/        (Game assets to be bundled into WASM)
web/
  ├── index.html     (Main game page)
  ├── webgl.js       (WebGL initialization)
  └── assets/        (General assets to be served)
```

## Technical Architecture

### Renderer System

The renderer is designed with a clear, stateful API that manages its own resources and batches WebGL operations efficiently:

```zig
// Initialize the renderer
var renderer = try Renderer.init(allocator, 800, 600);
defer renderer.deinit(allocator);

// In game loop:
renderer.beginFrame(.{ 0, 0, 0 });  // Clear screen
renderer.drawRect(10, 10, 100, 50, .{ 255, 0, 0 });  // Draw shapes
renderer.drawCircle(400, 300, 25, .{ 0, 255, 0 });
renderer.endFrame();  // Submit to WebGL
```

#### Key Features

1. **Resource Management**
   - Automatic frame buffer management
   - Safe resource cleanup with defer
   - No manual texture or buffer handling needed

2. **Command Buffer System**
   ```zig
   const CommandBuffer = struct {
       commands: []u32,
       count: usize,
       capacity: usize,
       // ... methods for batching commands
   };
   ```
   - Batches WebGL operations for efficiency
   - Minimizes JS-WASM boundary crossings
   - Automatic command submission

3. **Drawing Primitives**
   ```zig
   pub const Renderer = struct {
       pub fn drawPixel(self: *Renderer, x: usize, y: usize, color: [3]u8) void;
       pub fn drawRect(self: *Renderer, x: usize, y: usize, width: usize, height: usize, color: [3]u8) void;
       pub fn drawCircle(self: *Renderer, center_x: usize, center_y: usize, radius: usize, color: [3]u8) void;
   };
   ```
   - Hardware-accelerated shape rendering
   - Pixel-perfect drawing operations
   - Bounds checking for safety

### Game Integration

The renderer integrates cleanly with game entities:

```zig
// In Bird entity
pub fn render(self: Bird, renderer: *Renderer) void {
    const x = @intFromFloat(@max(0, @min(self.x, GAME_WIDTH - 1)));
    const y = @intFromFloat(@max(0, @min(self.y, GAME_HEIGHT - 1)));
    renderer.drawCircle(x, y, BIRD_SIZE / 2, .{ 255, 255, 0 });
}

// In Game update loop
pub fn renderGame(self: *Game) void {
    self.renderer.beginFrame(.{ 135, 206, 235 });  // Sky blue
    
    // Draw game objects
    self.bird.render(&self.renderer);
    for (self.pipes[0..self.pipe_count]) |*pipe| {
        pipe.render(&self.renderer);
    }
    
    self.renderer.endFrame();
}
```

### Performance Optimizations

1. **Command Batching**
   - All draw calls are batched into a single WebGL texture update
   - Single draw call per frame
   - Minimal state changes

2. **Memory Management**
   - Single frame buffer allocation at initialization
   - No per-frame allocations
   - Efficient memory reuse

3. **Frame Timing**
   - Intelligent frame rate limiting for different game states
   - Menu: 10 FPS to save resources
   - Game: Full frame rate for smooth gameplay
   - Paused/GameOver: Reduced updates

## API Reference

### Renderer

```zig
pub const Renderer = struct {
    // Initialization
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Renderer;
    pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void;

    // Frame Control
    pub fn beginFrame(self: *Renderer, clear_color: [3]u8) void;
    pub fn endFrame(self: *Renderer) void;

    // Drawing Operations
    pub fn drawPixel(self: *Renderer, x: usize, y: usize, color: [3]u8) void;
    pub fn drawRect(self: *Renderer, x: usize, y: usize, width: usize, height: usize, color: [3]u8) void;
    pub fn drawCircle(self: *Renderer, center_x: usize, center_y: usize, radius: usize, color: [3]u8) void;
};
```

### Usage Example

```zig
// Game initialization
pub fn init(allocator: std.mem.Allocator) !Game {
    return Game{
        .renderer = try Renderer.init(allocator, GAME_WIDTH, GAME_HEIGHT),
        // ... other initialization
    };
}

// Game rendering
pub fn render(self: *Game) void {
    self.renderer.beginFrame(.{ 135, 206, 235 });  // Clear to sky blue
    
    // Draw background
    self.renderer.drawRect(0, GAME_HEIGHT - 50, GAME_WIDTH, 50, .{ 83, 54, 10 });
    
    // Draw entities
    self.player.render(&self.renderer);
    for (self.objects) |*obj| {
        obj.render(&self.renderer);
    }
    
    self.renderer.endFrame();
}
```

## TODOs:
- [ ] Update canvas size. Currently we set size in index.html AND entities.zig - We should have one source of truth and it should be easily adjustable (different aspect ratios, etc) by future developers to give desktop vs mobile options.
- [ ] Implement threading? or just forgo this and move straight to new webgpu template.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with the Zig programming language
- Inspired by modern game development practices
- WebAssembly and WebGL communities