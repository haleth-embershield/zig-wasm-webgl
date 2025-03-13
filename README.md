# Zig-WASM-WebGL Game Template

A modern, high-performance game development template using Zig, WebAssembly, and WebGL. This template provides a solid foundation for building browser-based games with excellent performance characteristics and memory safety.

## Features

- **WebAssembly Integration**: Compile Zig code to WebAssembly for near-native performance in the browser
- **WebGL Rendering**: Hardware-accelerated graphics with a simple but powerful abstraction layer
- **Memory-Safe Architecture**: Leverages Zig's memory safety features for robust game development
- **Optimized Build Pipeline**: Streamlined build process with development server included
- **Cross-Platform**: Works on any modern browser that supports WebAssembly and WebGL
- **Responsive Design**: Adapts to different screen sizes and device capabilities

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

- `src/`: Contains the Zig source code
  - `src/main.zig`: Main game logic and WebAssembly exports
  - `src/renderer.zig`: Rendering engine implementation
  - `src/bitmap.zig`: Font/bitmap data handling
- `web/`: Contains HTML, CSS, JavaScript, and asset files
  - `web/index.html`: Main game page and JavaScript code
  - `web/webgl.js`: WebGL rendering implementation
  - `web/audio/`: Game sound assets
- `build.zig`: Build configuration for Zig
- `setup_zerver.zig`: Helper for setting up the development server

## Technical Architecture

### WebAssembly Integration

The template uses WebAssembly to run Zig code in the browser with near-native performance:

1. **Optimized Compilation**
   - Uses Zig's ReleaseFast mode for optimized WebAssembly output
   - Reduces warm-up jitter in the browser
   - Improves startup time and initial frame rates

2. **JavaScript-Zig Interop**
   - Clean interface between JavaScript and WebAssembly
   - Minimizes boundary crossing overhead
   - Provides simple exported functions for game lifecycle management

### Rendering Pipeline

The rendering system is designed for flexibility and performance:

1. **WebGL Acceleration**
   - Hardware-accelerated rendering through WebGL
   - Efficient texture management
   - Optimized draw calls

2. **Batched Rendering**
   - Groups related rendering operations
   - Minimizes state changes
   - Reduces CPU overhead

### Memory Management

The template implements several memory safety features:

1. **Safe Resource Management**
   - Proper initialization and cleanup of resources
   - Defensive memory allocation with error handling
   - Clear ownership semantics for allocated memory

2. **Preallocated Buffers**
   - Eliminates per-frame memory allocations
   - Provides stable memory footprint during gameplay
   - Reduces garbage collection pauses

## Customizing the Template

### Creating Your Game

1. **Modify Game Logic**
   - Edit `src/main.zig` to implement your game mechanics
   - Add new Zig files for additional game systems

2. **Customize Rendering**
   - Modify `src/renderer.zig` to change rendering approach
   - Update WebGL code in `web/webgl.js` for custom effects

3. **Add Assets**
   - Place audio files in `web/audio/`
   - Add images and other assets to the web directory
   - Update HTML/CSS in `web/index.html` for your game's UI

### Performance Optimization

For optimal performance, consider these best practices:

1. **Minimize Wasm-JS Boundary Crossings**
   - Batch related operations when possible
   - Pass larger chunks of data rather than many small pieces
   - Use shared memory for frequent data exchange

2. **Optimize Memory Usage**
   - Preallocate buffers for frequently used data
   - Reuse memory when possible
   - Be mindful of allocation patterns

3. **Efficient Rendering**
   - Batch similar draw calls
   - Minimize texture switches
   - Use appropriate data structures for spatial partitioning

## Advanced Customization

### WebGL Extensions

The template can be extended with additional WebGL features:

```javascript
// Example of adding WebGL extensions in webgl.js
function initWebGL() {
    // ... existing initialization code ...
    
    // Add extensions for advanced features
    const ext = gl.getExtension('OES_texture_float');
    if (ext) {
        // Use floating point textures
    }
}
```

### Custom Shaders

You can implement custom shaders for special effects:

```javascript
// Example of custom shader implementation
const customVertexShader = `
    attribute vec4 aVertexPosition;
    attribute vec2 aTextureCoord;
    
    uniform mat4 uModelViewMatrix;
    uniform mat4 uProjectionMatrix;
    
    varying highp vec2 vTextureCoord;
    
    void main(void) {
        gl_Position = uProjectionMatrix * uModelViewMatrix * aVertexPosition;
        vTextureCoord = aTextureCoord;
    }
`;
```

## Roadmap for Template Improvement

- [ ] Add WebGPU support as an alternative to WebGL
- [ ] Implement asset loading and management system
- [ ] Add physics integration options
- [ ] Create component-based game architecture
- [ ] Improve debugging and profiling tools
- [ ] Add support for multiple rendering backends

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with the Zig programming language
- Inspired by modern game development practices
- WebAssembly and WebGL communities