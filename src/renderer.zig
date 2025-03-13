const std = @import("std");

// -----------------------
// WebGL COMMAND SYSTEM
// -----------------------

/// WebGL command types for batched rendering
pub const WebGLCommand = enum(u32) {
    UploadTexture = 1,
    DrawArrays = 2,
};

/// Command buffer for batching WebGL operations
pub const CommandBuffer = struct {
    commands: []u32,
    count: usize,
    capacity: usize,

    /// Initialize a new command buffer with the given capacity
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !CommandBuffer {
        const commands = try allocator.alloc(u32, capacity * 4 + 1);
        @memset(commands, 0);
        return CommandBuffer{
            .commands = commands,
            .count = 0,
            .capacity = capacity,
        };
    }

    /// Free resources used by the command buffer
    pub fn deinit(self: *CommandBuffer, allocator: std.mem.Allocator) void {
        allocator.free(self.commands);
        self.commands = &[_]u32{};
        self.count = 0;
        self.capacity = 0;
    }

    /// Reset the command buffer for reuse
    pub fn reset(self: *CommandBuffer) void {
        self.count = 0;
    }

    /// Add a texture upload command to the buffer
    pub fn addTextureCommand(self: *CommandBuffer, data_ptr: [*]const u8) void {
        if (self.count >= self.capacity) return;

        const index = self.count * 4 + 1;
        self.commands[index] = @intFromEnum(WebGLCommand.UploadTexture);
        self.commands[index + 1] = @intFromPtr(data_ptr);
        self.count += 1;
    }

    /// Add a draw command to the buffer
    pub fn addDrawCommand(self: *CommandBuffer) void {
        if (self.count >= self.capacity) return;

        const index = self.count * 4 + 1;
        self.commands[index] = @intFromEnum(WebGLCommand.DrawArrays);
        self.count += 1;
    }

    /// Get a pointer to the command buffer for passing to WebGL
    pub fn getBufferPtr(self: *CommandBuffer) [*]u32 {
        self.commands[0] = @intCast(self.count);
        return self.commands.ptr;
    }
};

// -----------------------
// IMAGE AND RENDERING
// -----------------------

/// Represents an image in memory
pub const Image = struct {
    data: []u8,
    width: usize,
    height: usize,
    channels: usize,

    /// Create a new image with specified dimensions and channel count
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, channels: usize) !Image {
        const data = try allocator.alloc(u8, width * height * channels);
        @memset(data, 0);

        return Image{
            .data = data,
            .width = width,
            .height = height,
            .channels = channels,
        };
    }

    /// Free resources used by an image
    pub fn deinit(self: Image, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }

    /// Clear the image with a color
    pub fn clear(self: Image, color: [3]u8) void {
        var i: usize = 0;
        while (i < self.width * self.height) : (i += 1) {
            const index = i * self.channels;
            self.data[index] = color[0];
            self.data[index + 1] = color[1];
            self.data[index + 2] = color[2];
        }
    }
};

// -----------------------
// DRAWING PRIMITIVES
// -----------------------

/// Draw a pixel in an image
pub fn drawPixel(img: Image, x: usize, y: usize, color: [3]u8) void {
    if (x >= img.width or y >= img.height) return;

    const index = (y * img.width + x) * img.channels;
    if (index + 2 < img.data.len) {
        img.data[index] = color[0];
        img.data[index + 1] = color[1];
        img.data[index + 2] = color[2];
    }
}

/// Draw a filled rectangle
pub fn drawRect(img: Image, x: usize, y: usize, width: usize, height: usize, color: [3]u8) void {
    const max_x = @min(x + width, img.width);
    const max_y = @min(y + height, img.height);

    for (y..max_y) |py| {
        for (x..max_x) |px| {
            drawPixel(img, px, py, color);
        }
    }
}

/// Draw a circle
pub fn drawCircle(img: Image, center_x: usize, center_y: usize, radius: usize, color: [3]u8) void {
    const r_squared = radius * radius;

    const min_x = if (center_x > radius) center_x - radius else 0;
    const min_y = if (center_y > radius) center_y - radius else 0;
    const max_x = @min(center_x + radius + 1, img.width);
    const max_y = @min(center_y + radius + 1, img.height);

    for (min_y..max_y) |py| {
        for (min_x..max_x) |px| {
            const dx = if (px > center_x) px - center_x else center_x - px;
            const dy = if (py > center_y) py - center_y else center_y - py;

            if (dx * dx + dy * dy <= r_squared) {
                drawPixel(img, px, py, color);
            }
        }
    }
}

// -----------------------
// WEBGL-WASM INTERFACE
// -----------------------

/// WebGL constants
const GL_TEXTURE_2D: u32 = 0x0DE1;
const GL_RGB: u32 = 0x1907;
const GL_UNSIGNED_BYTE: u32 = 0x1401;
const GL_TRIANGLE_STRIP: u32 = 0x0005;

/// WebGL function bindings
extern fn glTexImage2D(target: u32, level: i32, internalformat: u32, width: i32, height: i32, border: i32, format: u32, type: u32, pixels: [*]const u8) void;
extern fn glDrawArrays(mode: u32, first: i32, count: i32) void;
extern fn consoleLog(ptr: [*]const u8, len: usize) void;

/// WebGL batched command execution function
extern "env" fn executeBatchedCommands(cmd_ptr: [*]u32, width: u32, height: u32) void;

/// Formal Renderer struct to encapsulate rendering functionality
pub const Renderer = struct {
    command_buffer: CommandBuffer,

    /// Initialize a new renderer
    pub fn init(allocator: std.mem.Allocator) !Renderer {
        const command_buffer = try CommandBuffer.init(allocator, 10);
        return Renderer{
            .command_buffer = command_buffer,
        };
    }

    /// Free resources used by the renderer
    pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
        self.command_buffer.deinit(allocator);
    }

    /// Begin a new frame
    pub fn beginFrame(self: *Renderer) void {
        self.command_buffer.reset();
    }

    /// End the current frame and render it
    pub fn endFrame(self: *Renderer, img: Image) void {
        // Add texture upload command
        self.command_buffer.addTextureCommand(img.data.ptr);

        // Add draw command
        self.command_buffer.addDrawCommand();

        // Execute the batched commands
        executeBatchedCommands(self.command_buffer.getBufferPtr(), @intCast(img.width), @intCast(img.height));
    }

    /// Draw a pixel
    pub fn drawPixel(self: *Renderer, img: *Image, x: usize, y: usize, color: [3]u8) void {
        _ = self; // Unused for now
        @This().drawPixel(img.*, x, y, color);
    }

    /// Draw a rectangle
    pub fn drawRect(self: *Renderer, img: *Image, x: usize, y: usize, width: usize, height: usize, color: [3]u8) void {
        _ = self; // Unused for now
        @This().drawRect(img.*, x, y, width, height, color);
    }

    /// Draw a circle
    pub fn drawCircle(self: *Renderer, img: *Image, center_x: usize, center_y: usize, radius: usize, color: [3]u8) void {
        _ = self; // Unused for now
        @This().drawCircle(img.*, center_x, center_y, radius, color);
    }
};

/// Render a frame with WebGL support using batched commands (legacy function for compatibility)
pub fn renderFrame(cmd_buffer: *CommandBuffer, img: Image) void {
    // Reset the command buffer
    cmd_buffer.reset();

    // Add texture upload command
    cmd_buffer.addTextureCommand(img.data.ptr);

    // Add draw command
    cmd_buffer.addDrawCommand();

    // Execute the batched commands
    executeBatchedCommands(cmd_buffer.getBufferPtr(), @intCast(img.width), @intCast(img.height));
}
