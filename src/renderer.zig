const std = @import("std");

/// WebGL command types for batched rendering
pub const WebGLCommand = enum(u32) {
    UploadTexture = 1,
    DrawArrays = 2,
};

/// Command buffer for batching WebGL operations
const CommandBuffer = struct {
    commands: []u32,
    count: usize,
    capacity: usize,

    fn init(allocator: std.mem.Allocator, capacity: usize) !CommandBuffer {
        const commands = try allocator.alloc(u32, capacity * 4 + 1);
        @memset(commands, 0);
        return CommandBuffer{
            .commands = commands,
            .count = 0,
            .capacity = capacity,
        };
    }

    fn deinit(self: *CommandBuffer, allocator: std.mem.Allocator) void {
        allocator.free(self.commands);
    }

    fn reset(self: *CommandBuffer) void {
        self.count = 0;
    }

    fn addTextureCommand(self: *CommandBuffer, data_ptr: [*]const u8) void {
        if (self.count >= self.capacity) return;

        const index = self.count * 4 + 1;
        self.commands[index] = @intFromEnum(WebGLCommand.UploadTexture);
        self.commands[index + 1] = @intFromPtr(data_ptr);
        self.count += 1;
    }

    fn addDrawCommand(self: *CommandBuffer) void {
        if (self.count >= self.capacity) return;

        const index = self.count * 4 + 1;
        self.commands[index] = @intFromEnum(WebGLCommand.DrawArrays);
        self.count += 1;
    }

    fn getBufferPtr(self: *CommandBuffer) [*]u32 {
        self.commands[0] = @intCast(self.count);
        return self.commands.ptr;
    }
};

/// Internal image buffer representation
const Image = struct {
    data: []u8,
    width: usize,
    height: usize,
    channels: usize,

    fn init(allocator: std.mem.Allocator, width: usize, height: usize, channels: usize) !Image {
        const data = try allocator.alloc(u8, width * height * channels);
        @memset(data, 0);
        return Image{ .data = data, .width = width, .height = height, .channels = channels };
    }

    fn deinit(self: Image, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }

    fn clear(self: Image, color: [3]u8) void {
        var i: usize = 0;
        while (i < self.width * self.height) : (i += 1) {
            const index = i * self.channels;
            self.data[index] = color[0];
            self.data[index + 1] = color[1];
            self.data[index + 2] = color[2];
        }
    }
};

/// WebGL function bindings
extern fn executeBatchedCommands(cmd_ptr: [*]u32, width: u32, height: u32) void;

/// Main renderer interface for the game
pub const Renderer = struct {
    command_buffer: CommandBuffer,
    frame_buffer: Image,

    /// Initialize a new renderer with a given resolution
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Renderer {
        return Renderer{
            .command_buffer = try CommandBuffer.init(allocator, 10),
            .frame_buffer = try Image.init(allocator, width, height, 3),
        };
    }

    /// Free all resources used by the renderer
    pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
        self.command_buffer.deinit(allocator);
        self.frame_buffer.deinit(allocator);
    }

    /// Start a new frame, clearing with the given color
    pub fn beginFrame(self: *Renderer, clear_color: [3]u8) void {
        self.command_buffer.reset();
        self.frame_buffer.clear(clear_color);
    }

    /// Finish frame and send commands to WebGL
    pub fn endFrame(self: *Renderer) void {
        self.command_buffer.addTextureCommand(self.frame_buffer.data.ptr);
        self.command_buffer.addDrawCommand();
        executeBatchedCommands(self.command_buffer.getBufferPtr(), @intCast(self.frame_buffer.width), @intCast(self.frame_buffer.height));
    }

    /// Draw a single pixel
    pub fn drawPixel(self: *Renderer, x: usize, y: usize, color: [3]u8) void {
        if (x >= self.frame_buffer.width or y >= self.frame_buffer.height) return;

        const index = (y * self.frame_buffer.width + x) * self.frame_buffer.channels;
        if (index + 2 < self.frame_buffer.data.len) {
            self.frame_buffer.data[index] = color[0];
            self.frame_buffer.data[index + 1] = color[1];
            self.frame_buffer.data[index + 2] = color[2];
        }
    }

    /// Draw a filled rectangle
    pub fn drawRect(self: *Renderer, x: usize, y: usize, width: usize, height: usize, color: [3]u8) void {
        const max_x = @min(x + width, self.frame_buffer.width);
        const max_y = @min(y + height, self.frame_buffer.height);

        for (y..max_y) |py| {
            for (x..max_x) |px| {
                self.drawPixel(px, py, color);
            }
        }
    }

    /// Draw a filled circle
    pub fn drawCircle(self: *Renderer, center_x: usize, center_y: usize, radius: usize, color: [3]u8) void {
        const r_squared = radius * radius;
        const min_x = if (center_x > radius) center_x - radius else 0;
        const min_y = if (center_y > radius) center_y - radius else 0;
        const max_x = @min(center_x + radius + 1, self.frame_buffer.width);
        const max_y = @min(center_y + radius + 1, self.frame_buffer.height);

        for (min_y..max_y) |py| {
            for (min_x..max_x) |px| {
                const dx = if (px > center_x) px - center_x else center_x - px;
                const dy = if (py > center_y) py - center_y else center_y - py;
                if (dx * dx + dy * dy <= r_squared) {
                    self.drawPixel(px, py, color);
                }
            }
        }
    }
};
