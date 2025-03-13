const std = @import("std");
const ascii = @import("ascii_converter.zig");

// -----------------------
// WebGL BINDINGS
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
// WebGL FUNCTIONS
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

/// New WebGL batched command execution function
extern "env" fn executeBatchedCommands(cmd_ptr: [*]u32, width: u32, height: u32) void;

// -----------------------
// RENDERING FUNCTIONS
// -----------------------

/// Render a frame with WebGL support using batched commands
/// This function creates a command buffer and executes it
pub fn render_game_frame_batched(cmd_buffer: *CommandBuffer, ptr: [*]u8, width: usize, height: usize, channels: usize) void {
    // Explicitly mark channels as used to avoid unused parameter warning
    _ = channels;

    // Reset the command buffer
    cmd_buffer.reset();

    // Add texture upload command
    cmd_buffer.addTextureCommand(ptr);

    // Add draw command
    cmd_buffer.addDrawCommand();

    // Execute the batched commands
    executeBatchedCommands(cmd_buffer.getBufferPtr(), @intCast(width), @intCast(height));
}

/// Render a frame with WebGL support
/// This public function uploads the texture to WebGL and handles rendering
/// Legacy function kept for compatibility
pub export fn render_game_frame(ptr: [*]u8, width: usize, height: usize, channels: usize) void {
    // Explicitly mark channels as used to avoid unused parameter warning
    _ = channels;

    // Upload texture to WebGL
    glTexImage2D(GL_TEXTURE_2D, 0, // level
        GL_RGB, // internal format
        @intCast(width), // width
        @intCast(height), // height
        0, // border
        GL_RGB, // format
        GL_UNSIGNED_BYTE, // type
        ptr // data
    );

    // Draw the quad
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

/// Generate ASCII art from an image
pub fn generateAsciiArt(
    allocator: std.mem.Allocator,
    img: Image,
    edge_result: ?EdgeData,
    params: RenderParams,
) ![]u8 {
    var out_w = (img.width / params.block_size) * params.block_size;
    var out_h = (img.height / params.block_size) * params.block_size;

    out_w = @max(out_w, 1);
    out_h = @max(out_h, 1);

    // Dithering error buffers
    var curr_ditherr = if (params.dither != .None)
        try allocator.alloc(u32, out_w)
    else
        null;
    var next_ditherr = if (params.dither != .None)
        try allocator.alloc(u32, out_w)
    else
        null;
    defer if (curr_ditherr) |buf| allocator.free(buf);
    defer if (next_ditherr) |buf| allocator.free(buf);

    // Initialize error buffers to 0 if they exist
    if (curr_ditherr) |buf| @memset(buf, 0);
    if (next_ditherr) |buf| @memset(buf, 0);

    const ascii_img = try allocator.alloc(u8, out_w * out_h * 3);
    @memset(ascii_img, 0);

    var y: usize = 0;
    while (y < out_h) : (y += params.block_size) {
        if (params.dither != .None) {
            @memset(next_ditherr.?, 0);
        }
        var x: usize = 0;
        while (x < out_w) : (x += params.block_size) {
            var block_info = calculateBlockInfo(img, edge_result, x, y, out_w, out_h, params);

            if (params.dither != .None) {
                const avg_brightness: u8 = @as(u8, @intCast(block_info.sum_brightness / block_info.pixel_count));

                const adjusted_brightness = @as(u32, @intCast(avg_brightness)) +
                    (if (curr_ditherr) |buf| buf[x / params.block_size] else 0);

                const clamped_brightness = @as(u8, @intCast(std.math.clamp(adjusted_brightness, 0, 255)));

                const closest = findClosestBrightness(clamped_brightness, params.ascii_chars, params.ascii_info);

                switch (params.dither) {
                    DitherType.FloydSteinberg => floydSteinberg(
                        curr_ditherr.?,
                        next_ditherr.?,
                        @as(u8, @intCast(x)) / params.block_size,
                        @as(u8, @intCast(out_w)) / params.block_size,
                        closest[1],
                    ),
                    DitherType.None => {},
                }

                block_info.sum_brightness = @as(u64, closest[0]) * block_info.pixel_count;
            }

            const ascii_char = selectAsciiChar(block_info, params);
            const avg_color = calculateAverageColor(block_info, params);

            try convertToAscii(ascii_img, out_w, out_h, x, y, ascii_char, avg_color, params.block_size, params.color, params);
        }

        if (curr_ditherr != null and next_ditherr != null) {
            const t = curr_ditherr;
            curr_ditherr = next_ditherr;
            next_ditherr = t;
            if (next_ditherr) |buf| @memset(buf, 0);
        }
    }

    return ascii_img;
}

/// Auto-adjust brightness and contrast
pub fn autoBrightnessContrast(
    allocator: std.mem.Allocator,
    img: Image,
    clip_hist_percent: f32,
) ![]u8 {
    const gray = try rgbToGrayscale(allocator, img);
    defer allocator.free(gray);

    // Calculate histogram / frequency distribution
    var hist = [_]usize{0} ** 256;
    for (gray) |px| {
        hist[px] += 1;
    }

    // Cumulative distribution
    var accumulator = [_]usize{0} ** 256;
    accumulator[0] = hist[0];
    for (1..256) |i| {
        accumulator[i] = accumulator[i - 1] + hist[i];
    }

    // Locate points to clip
    const max = accumulator[255];
    const clip_hist_count = @as(usize, @intFromFloat(@as(f32, @floatFromInt(max)) * clip_hist_percent / 100.0 / 2.0));

    // Locate left cut
    var min_gray: usize = 0;
    while (accumulator[min_gray] < clip_hist_count) : (min_gray += 1) {}

    // Locate right cut
    var max_gray: usize = 255;
    while (accumulator[max_gray] >= (max - clip_hist_count)) : (max_gray -= 1) {}

    // Calculate alpha and beta values
    const alpha = 255.0 / @as(f32, @floatFromInt(max_gray - min_gray));
    const beta = -@as(f32, @floatFromInt(min_gray)) * alpha;

    // Apply brightness and contrast adjustment
    const len = img.width * img.height * img.channels;
    var res = try allocator.alloc(u8, len);
    for (0..len) |i| {
        const adjusted = @as(f32, @floatFromInt(img.data[i])) * alpha + beta;
        res[i] = @intFromFloat(std.math.clamp(adjusted, 0, 255));
    }

    return res;
}

/// Create a new image by resizing an existing one
pub fn resizeImage(allocator: std.mem.Allocator, img: Image, new_width: usize, new_height: usize) !Image {
    // Safety checks
    if (img.width == 0 or img.height == 0 or new_width == 0 or new_height == 0) {
        return error.InvalidDimensions;
    }

    const total_pixels = new_width * new_height;
    const buffer_size = total_pixels * img.channels;

    var scaled_data = try allocator.alloc(u8, buffer_size);
    errdefer allocator.free(scaled_data);

    // Simple nearest-neighbor resize for WebAssembly implementation
    // This avoids dependencies on external libraries like stb
    const x_ratio = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(new_width));
    const y_ratio = @as(f32, @floatFromInt(img.height)) / @as(f32, @floatFromInt(new_height));

    for (0..new_height) |y| {
        for (0..new_width) |x| {
            const src_x = @as(usize, @intFromFloat(@floor(@as(f32, @floatFromInt(x)) * x_ratio)));
            const src_y = @as(usize, @intFromFloat(@floor(@as(f32, @floatFromInt(y)) * y_ratio)));

            const src_index = (src_y * img.width + src_x) * img.channels;
            const dst_index = (y * new_width + x) * img.channels;

            @memcpy(scaled_data[dst_index .. dst_index + img.channels], img.data[src_index .. src_index + img.channels]);
        }
    }

    return Image{
        .data = scaled_data,
        .width = new_width,
        .height = new_height,
        .channels = img.channels,
    };
}

// -----------------------
// PUBLIC API FOR GAMES
// -----------------------

/// Create a new renderer configuration with default settings
pub fn createRenderer(allocator: std.mem.Allocator) !RenderParams {
    const ascii_chars = DEFAULT_ASCII; // Use the constant instead of hardcoding
    const ascii_info = try initAsciiChars(allocator, ascii_chars);

    return RenderParams{
        .ascii_chars = ascii_chars,
        .ascii_info = ascii_info,
        .color = true,
        .invert_color = false,
        .block_size = 8, // Reduced from 8 to 4 for better resolution
        .detect_edges = false,
        .sigma1 = 0.5,
        .sigma2 = 1.0,
        .brightness_boost = 1.5,
        .threshold_disabled = false,
        .dither = .None,
        .bg_color = null,
        .fg_color = null,
        .use_ascii = true,
    };
}

/// Create a new image with specified dimensions and channel count
pub fn createImage(allocator: std.mem.Allocator, width: usize, height: usize, channels: usize) !Image {
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
pub fn destroyImage(allocator: std.mem.Allocator, img: Image) void {
    allocator.free(img.data);
}

/// Render an RGB image as ASCII art
pub fn renderToAscii(
    allocator: std.mem.Allocator,
    img: Image,
    params: RenderParams,
) ![]u8 {
    // Safety checks
    if (img.width == 0 or img.height == 0) {
        return error.InvalidImageDimensions;
    }

    // Validate image data
    if (img.data.len < img.width * img.height * img.channels) {
        return error.InvalidImageData;
    }

    // Use the global preallocated buffer if available and correctly sized
    var output_buffer: []u8 = undefined;
    var using_global_buffer = false;

    if (global_ascii_buffer) |buffer| {
        if (buffer.len >= img.width * img.height * img.channels) {
            output_buffer = buffer;
            using_global_buffer = true;
        } else {
            // If buffer exists but wrong size, allocate a new one
            output_buffer = try allocator.alloc(u8, img.width * img.height * img.channels);
        }
    } else {
        // If no global buffer, allocate a new one
        output_buffer = try allocator.alloc(u8, img.width * img.height * img.channels);
    }

    // Initialize output buffer to zero
    @memset(output_buffer, 0);

    // Calculate output dimensions based on block size
    const out_w = @max((img.width / params.block_size) * params.block_size, 1);
    const out_h = @max((img.height / params.block_size) * params.block_size, 1);

    // Define colors
    const background_color = if (params.bg_color != null) params.bg_color.? else [3]u8{ 21, 9, 27 }; // Dark purple
    const text_color = if (params.fg_color != null) params.fg_color.? else [3]u8{ 211, 106, 111 }; // Light red

    // Process pixels in a single pass with minimal branching
    var y: usize = 0;
    while (y < out_h) : (y += params.block_size) {
        var x: usize = 0;
        while (x < out_w) : (x += params.block_size) {
            // Calculate block boundaries with bounds checking
            const max_y = @min(y + params.block_size, out_h);
            const max_x = @min(x + params.block_size, out_w);

            // Calculate block info
            var sum_brightness: u64 = 0;
            var sum_color = [3]u64{ 0, 0, 0 };
            var pixel_count: u64 = 0;

            // Process each pixel in the block
            var by: usize = y;
            while (by < max_y) : (by += 1) {
                var bx: usize = x;
                while (bx < max_x) : (bx += 1) {
                    // Bounds check for input image
                    if (bx >= img.width or by >= img.height) {
                        continue;
                    }

                    const pixel_index = (by * img.width + bx) * img.channels;

                    // Bounds check for pixel data
                    if (pixel_index + 2 >= img.data.len) {
                        continue;
                    }

                    const r = img.data[pixel_index];
                    const g = img.data[pixel_index + 1];
                    const b = img.data[pixel_index + 2];

                    // Calculate grayscale value
                    const gray: u64 = @intFromFloat(@as(f32, @floatFromInt(r)) * 0.3 +
                        @as(f32, @floatFromInt(g)) * 0.59 +
                        @as(f32, @floatFromInt(b)) * 0.11);

                    sum_brightness += gray;

                    if (params.color) {
                        sum_color[0] += r;
                        sum_color[1] += g;
                        sum_color[2] += b;
                    }

                    pixel_count += 1;
                }
            }

            // Skip empty blocks
            if (pixel_count == 0) {
                continue;
            }

            // Calculate average brightness and select ASCII character
            const avg_brightness: usize = @intCast(sum_brightness / pixel_count);
            const boosted_brightness: usize = @intFromFloat(@as(f32, @floatFromInt(avg_brightness)) * params.brightness_boost);
            const clamped_brightness = std.math.clamp(boosted_brightness, 0, 255);

            // Select ASCII character
            const char_index = (clamped_brightness * params.ascii_chars.len) / 256;
            const selected_char = params.ascii_info[@min(char_index, params.ascii_info.len - 1)];
            const ascii_char = params.ascii_chars[selected_char.start .. selected_char.start + selected_char.len];

            // Calculate average color
            var avg_color = [3]u8{ 255, 255, 255 };
            if (params.color) {
                avg_color = [3]u8{
                    @intCast(sum_color[0] / pixel_count),
                    @intCast(sum_color[1] / pixel_count),
                    @intCast(sum_color[2] / pixel_count),
                };

                if (params.invert_color) {
                    avg_color[0] = 255 - avg_color[0];
                    avg_color[1] = 255 - avg_color[1];
                    avg_color[2] = 255 - avg_color[2];
                }
            }

            // Get bitmap for the character
            const bm = &(try bitmap.getCharBitmap(ascii_char));

            // Render the character to the output buffer
            var dy: usize = 0;
            while (dy < max_y - y) : (dy += 1) {
                var dx: usize = 0;
                while (dx < max_x - x) : (dx += 1) {
                    const out_x = x + dx;
                    const out_y = y + dy;

                    // Bounds check for output buffer
                    if (out_x >= out_w or out_y >= out_h) {
                        continue;
                    }

                    const out_idx = (out_y * out_w + out_x) * 3;

                    // Bounds check for output buffer
                    if (out_idx + 2 >= output_buffer.len) {
                        continue;
                    }

                    // Check if this pixel is part of the character
                    const shift: u3 = @intCast(7 - @min(dx, 7));
                    const bit: u8 = @as(u8, 1) << shift;

                    if (dy < 8 and (bm[dy] & bit) != 0) {
                        // Character pixel: use color
                        if (params.color) {
                            output_buffer[out_idx] = avg_color[0];
                            output_buffer[out_idx + 1] = avg_color[1];
                            output_buffer[out_idx + 2] = avg_color[2];
                        } else {
                            output_buffer[out_idx] = text_color[0];
                            output_buffer[out_idx + 1] = text_color[1];
                            output_buffer[out_idx + 2] = text_color[2];
                        }
                    } else {
                        // Not a character pixel: use background
                        if (params.color) {
                            output_buffer[out_idx] = 0;
                            output_buffer[out_idx + 1] = 0;
                            output_buffer[out_idx + 2] = 0;
                        } else {
                            output_buffer[out_idx] = background_color[0];
                            output_buffer[out_idx + 1] = background_color[1];
                            output_buffer[out_idx + 2] = background_color[2];
                        }
                    }
                }
            }
        }
    }

    // If we're using the global buffer, return it directly
    if (using_global_buffer) {
        return output_buffer;
    } else {
        // Otherwise, return the newly allocated buffer
        return output_buffer;
    }
}

/// Draw a pixel in an image (utility for game rendering)
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

    // Ensure we don't go out of bounds
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

/// Clear the image with a color
pub fn clearImage(img: Image, color: [3]u8) void {
    var i: usize = 0;
    while (i < img.width * img.height) : (i += 1) {
        const index = i * img.channels;
        img.data[index] = color[0];
        img.data[index + 1] = color[1];
        img.data[index + 2] = color[2];
    }
}

/// Simple example game-style rendering function (for a flappy bird style game)
pub fn renderGameFrame(
    allocator: std.mem.Allocator,
    renderer: RenderParams,
    game_width: usize,
    game_height: usize,
    bird_x: usize,
    bird_y: usize,
    pipes: [][4]usize, // Array of [x, top_height, bottom_y, width]
    score: usize, // Used for displaying score in future implementations
) ![]u8 {
    // Create a game frame image
    const frame = try createImage(allocator, game_width, game_height, 3);
    defer destroyImage(allocator, frame);

    // Draw background
    clearImage(frame, .{ 135, 206, 235 }); // Sky blue

    // Draw ground
    drawRect(frame, 0, game_height - 20, game_width, 20, .{ 139, 69, 19 }); // Brown

    // Draw pipes
    for (pipes) |pipe| {
        const pipe_x = pipe[0];
        const top_height = pipe[1];
        const bottom_y = pipe[2];
        const pipe_width = pipe[3];

        // Top pipe
        drawRect(frame, pipe_x, 0, pipe_width, top_height, .{ 0, 128, 0 }); // Green

        // Bottom pipe
        drawRect(frame, pipe_x, bottom_y, pipe_width, game_height - bottom_y, .{ 0, 128, 0 }); // Green
    }

    // Draw bird
    drawCircle(frame, bird_x, bird_y, 10, .{ 255, 255, 0 }); // Yellow

    // TODO: Display score in future implementation
    _ = score; // Explicitly mark as used to avoid unused parameter warning

    // Convert to ASCII art
    return renderToAscii(allocator, frame, renderer);
}
