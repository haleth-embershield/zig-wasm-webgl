const std = @import("std");

// -----------------------
// FONT BITMAP DATA
// -----------------------

const bitmap = @import("bitmap.zig");

// -----------------------
// CHARACTER SETS
// -----------------------

/// Different character sets for ASCII rendering
pub const DEFAULT_ASCII = " .:-=+*%@#";
pub const DEFAULT_BLOCK = " .:coPO?@█";
pub const FULL_CHARACTERS = " .-:=+iltIcsv1x%7aejorzfnuCJT3*69LYpqy25SbdgFGOVXkPhmw48AQDEHKUZR@B#NW0M";

/// A simplified ASCII renderer targeting WebAssembly for a Flappy Bird-like game
/// Extracted and optimized from the original glyph project

// -----------------------
// TYPES AND CONSTANTS
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

/// Preallocated buffer for ASCII output to avoid per-frame allocations
var global_ascii_buffer: ?[]u8 = null;

/// Preallocate a buffer for ASCII rendering to avoid per-frame allocations
pub fn preallocateAsciiBuffer(allocator: std.mem.Allocator, width: usize, height: usize) !void {
    // Free any existing buffer
    if (global_ascii_buffer) |buffer| {
        allocator.free(buffer);
        global_ascii_buffer = null;
    }

    // Allocate a new buffer with appropriate size (3 bytes per pixel for RGB)
    global_ascii_buffer = try allocator.alloc(u8, width * height * 3);

    // Initialize buffer to zero
    @memset(global_ascii_buffer.?, 0);
}

/// Free the global ASCII buffer
pub fn freeAsciiBuffer(allocator: std.mem.Allocator) void {
    if (global_ascii_buffer) |buffer| {
        allocator.free(buffer);
        global_ascii_buffer = null;
    }
}

/// Represents an image in memory
pub const Image = struct {
    data: []u8,
    width: usize,
    height: usize,
    channels: usize,
};

/// Stores information about edges in the image
pub const EdgeData = struct {
    grayscale: []u8,
    magnitude: []f32,
    direction: []f32,
};

/// Information about a character in the ASCII character set
pub const AsciiCharInfo = struct { start: usize, len: u8 };

/// Available dithering options
pub const DitherType = enum { FloydSteinberg, None };

/// Parameters for the ASCII renderer
pub const RenderParams = struct {
    /// ASCII characters to use (from low to high brightness)
    ascii_chars: []const u8 = " .:-=+*%@#",
    /// Processed ASCII character information
    ascii_info: []AsciiCharInfo,
    /// Enable colored output
    color: bool = false,
    /// Invert colors
    invert_color: bool = false,
    /// Size of each character block in pixels
    block_size: u8 = 8,
    /// Edge detection
    detect_edges: bool = false,
    /// Sigma parameters for edge detection
    sigma1: f32 = 0.5,
    sigma2: f32 = 1.0,
    /// Brightness boost multiplier
    brightness_boost: f32 = 1.0,
    /// Disable threshold for edge detection
    threshold_disabled: bool = false,
    /// Type of dithering
    dither: DitherType = .None,
    /// Background color (RGB)
    bg_color: ?[3]u8 = null,
    /// Foreground color (RGB)
    fg_color: ?[3]u8 = null,
    /// Toggle ASCII rendering on/off
    use_ascii: bool = true,

    /// Free allocated resources
    pub fn deinit(self: *RenderParams, allocator: std.mem.Allocator) void {
        allocator.free(self.ascii_info);
    }
};

/// Temporarily holds information about a block of pixels
const BlockInfo = struct {
    sum_brightness: u64 = 0,
    sum_color: [3]u64 = .{ 0, 0, 0 },
    pixel_count: u64 = 0,
    sum_mag: f32 = 0,
    sum_dir: f32 = 0,
};

// -----------------------
// WebGL BINDINGS
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

/// Initialize ASCII character information from a string of ASCII characters
pub fn initAsciiChars(allocator: std.mem.Allocator, ascii_chars: []const u8) ![]AsciiCharInfo {
    var char_info = std.ArrayList(AsciiCharInfo).init(allocator);
    defer char_info.deinit();

    var i: usize = 0;
    while (i < ascii_chars.len) {
        const len = try std.unicode.utf8ByteSequenceLength(ascii_chars[i]);
        try char_info.append(.{ .start = i, .len = @intCast(len) });
        i += len;
    }

    return char_info.toOwnedSlice();
}

/// Convert RGB image to grayscale
pub fn rgbToGrayscale(allocator: std.mem.Allocator, img: Image) ![]u8 {
    const grayscale_img = try allocator.alloc(u8, img.width * img.height);
    errdefer allocator.free(grayscale_img);

    for (0..img.height) |y| {
        for (0..img.width) |x| {
            const i = (y * img.width + x) * img.channels;
            if (i + 2 >= img.width * img.height * img.channels) {
                continue; // Skip if accessing out of bounds
            }
            const r = img.data[i];
            const g = img.data[i + 1];
            const b = img.data[i + 2];
            grayscale_img[y * img.width + x] = @intFromFloat((0.299 * @as(f32, @floatFromInt(r)) +
                0.587 * @as(f32, @floatFromInt(g)) +
                0.114 * @as(f32, @floatFromInt(b))));
        }
    }
    return grayscale_img;
}

/// Apply a Gaussian blur to an image
fn gaussianKernel(allocator: std.mem.Allocator, sigma: f32) ![]f32 {
    const size: usize = @intFromFloat(6 * sigma);
    const kernel_size = if (size % 2 == 0) size + 1 else size;
    const half: f32 = @floatFromInt(kernel_size / 2);

    var kernel = try allocator.alloc(f32, kernel_size);
    var sum: f32 = 0;

    for (0..kernel_size) |i| {
        const x = @as(f32, @floatFromInt(i)) - half;
        kernel[i] = @exp(-(x * x) / (2 * sigma * sigma));
        sum += kernel[i];
    }

    // Normalize the kernel
    for (0..kernel_size) |i| {
        kernel[i] /= sum;
    }

    return kernel;
}

/// Apply Gaussian blur to grayscale image
fn applyGaussianBlur(allocator: std.mem.Allocator, img: Image, sigma: f32) ![]u8 {
    const kernel = try gaussianKernel(allocator, sigma);
    defer allocator.free(kernel);

    var temp = try allocator.alloc(u8, img.width * img.height);
    defer allocator.free(temp);
    var res = try allocator.alloc(u8, img.width * img.height);

    // Horizontal pass
    for (0..img.height) |y| {
        for (0..img.width) |x| {
            var sum: f32 = 0;
            for (0..kernel.len) |i| {
                const ix: i32 = @as(i32, @intCast(x)) + @as(i32, @intCast(i)) - @as(i32, @intCast(kernel.len / 2));
                if (ix >= 0 and ix < img.width) {
                    sum += @as(f32, @floatFromInt(img.data[y * img.width + @as(usize, @intCast(ix))])) * kernel[i];
                }
            }
            temp[y * img.width + x] = @intFromFloat(sum);
        }
    }

    // Vertical pass
    for (0..img.height) |y| {
        for (0..img.width) |x| {
            var sum: f32 = 0;
            for (0..kernel.len) |i| {
                const iy: i32 = @as(i32, @intCast(y)) + @as(i32, @intCast(i)) - @as(i32, @intCast(kernel.len / 2));
                if (iy >= 0 and iy < img.height) {
                    sum += @as(f32, @floatFromInt(temp[@as(usize, @intCast(iy)) * img.width + x])) * kernel[i];
                }
            }
            res[y * img.width + x] = @intFromFloat(sum);
        }
    }

    return res;
}

/// Apply difference of Gaussians to detect edges
fn differenceOfGaussians(allocator: std.mem.Allocator, img: Image, sigma1: f32, sigma2: f32) ![]u8 {
    const blur1 = try applyGaussianBlur(allocator, img, sigma1);
    defer allocator.free(blur1);
    const blur2 = try applyGaussianBlur(allocator, img, sigma2);
    defer allocator.free(blur2);

    var res = try allocator.alloc(u8, img.width * img.height);
    for (0..img.width * img.height) |i| {
        const diff = @as(i16, blur1[i]) - @as(i16, blur2[i]);
        res[i] = @as(u8, @intCast(std.math.clamp(diff + 128, 0, 255)));
    }

    return res;
}

/// Apply Sobel filter to detect edges
fn applySobelFilter(allocator: std.mem.Allocator, img: Image) !struct { magnitude: []f32, direction: []f32 } {
    const Gx = [_][3]i32{ .{ -1, 0, 1 }, .{ -2, 0, 2 }, .{ -1, 0, 1 } };
    const Gy = [_][3]i32{ .{ -1, -2, -1 }, .{ 0, 0, 0 }, .{ 1, 2, 1 } };

    var mag = try allocator.alloc(f32, img.width * img.height);
    errdefer allocator.free(mag);

    var dir = try allocator.alloc(f32, img.width * img.height);
    errdefer allocator.free(dir);

    // Initialize arrays to avoid uninitialized memory
    @memset(mag, 0);
    @memset(dir, 0);

    // Skip edge processing if image is too small
    if (img.width < 3 or img.height < 3) {
        return .{
            .magnitude = mag,
            .direction = dir,
        };
    }

    // Handle bounds to prevent integer overflow
    const height_max = if (img.height > 0) img.height - 1 else 0;
    const width_max = if (img.width > 0) img.width - 1 else 0;

    // Process the inner part of the image (skip borders)
    var y: usize = 1;
    while (y < height_max) : (y += 1) {
        var x: usize = 1;
        while (x < width_max) : (x += 1) {
            var gx: f32 = 0;
            var gy: f32 = 0;

            for (0..3) |i| {
                for (0..3) |j| {
                    const pixel_idx = (y + i - 1) * img.width + (x + j - 1);
                    if (pixel_idx < img.width * img.height) {
                        const pixel = img.data[pixel_idx];
                        gx += @as(f32, @floatFromInt(Gx[i][j])) * @as(f32, @floatFromInt(pixel));
                        gy += @as(f32, @floatFromInt(Gy[i][j])) * @as(f32, @floatFromInt(pixel));
                    }
                }
            }

            const idx = y * img.width + x;
            if (idx < img.width * img.height) {
                mag[idx] = @sqrt(gx * gx + gy * gy);
                dir[idx] = std.math.atan2(gy, gx);
            }
        }
    }

    return .{
        .magnitude = mag,
        .direction = dir,
    };
}

/// Detect edges in an image
pub fn detectEdges(allocator: std.mem.Allocator, img: Image, detect_edges: bool, sigma1: f32, sigma2: f32) !?EdgeData {
    if (!detect_edges) {
        return null;
    }

    // Handle invalid image dimensions
    if (img.width == 0 or img.height == 0) {
        const empty_u8 = try allocator.alloc(u8, 0);
        const empty_f32_1 = try allocator.alloc(f32, 0);
        const empty_f32_2 = try allocator.alloc(f32, 0);

        return .{
            .grayscale = empty_u8,
            .magnitude = empty_f32_1,
            .direction = empty_f32_2,
        };
    }

    const grayscale_img = try rgbToGrayscale(allocator, img);
    errdefer allocator.free(grayscale_img);

    // Validate grayscale image
    if (grayscale_img.len == 0) {
        const empty_f32_1 = try allocator.alloc(f32, 0);
        const empty_f32_2 = try allocator.alloc(f32, 0);

        return .{
            .grayscale = grayscale_img,
            .magnitude = empty_f32_1,
            .direction = empty_f32_2,
        };
    }

    const dog_img = try differenceOfGaussians(allocator, .{
        .data = grayscale_img,
        .width = img.width,
        .height = img.height,
        .channels = 1, // Important: grayscale is 1 channel
    }, sigma1, sigma2);
    defer allocator.free(dog_img);

    const edge_result = try applySobelFilter(allocator, .{
        .data = dog_img,
        .width = img.width,
        .height = img.height,
        .channels = 1,
    });

    return .{
        .grayscale = grayscale_img,
        .magnitude = edge_result.magnitude,
        .direction = edge_result.direction,
    };
}

/// Determine if a point is an edge
fn getEdgeChar(mag: f32, dir: f32, threshold_disabled: bool) ?u8 {
    const threshold: f32 = 50;
    if (mag < threshold and !threshold_disabled) {
        return null;
    }

    const angle = (dir + std.math.pi) * (@as(f32, 180) / std.math.pi);
    return switch (@as(u8, @intFromFloat(@mod(angle + 22.5, 180) / 45))) {
        0, 4 => '-',
        1, 5 => '\\',
        2, 6 => '|',
        3, 7 => '/',
        else => unreachable,
    };
}

/// Calculate information about a block of pixels
pub fn calculateBlockInfo(
    img: Image,
    edge_result: ?EdgeData,
    x: usize,
    y: usize,
    out_w: usize,
    out_h: usize,
    params: RenderParams,
) BlockInfo {
    var info = BlockInfo{ .sum_brightness = 0, .sum_color = .{ 0, 0, 0 }, .pixel_count = 0, .sum_mag = 0, .sum_dir = 0 };

    const block_w = @min(params.block_size, out_w - x);
    const block_h = @min(params.block_size, out_h - y);

    for (0..block_h) |dy| {
        for (0..block_w) |dx| {
            const ix = x + dx;
            const iy = y + dy;
            if (ix >= img.width or iy >= img.height) {
                continue;
            }
            const pixel_index = (iy * img.width + ix) * img.channels;
            if (pixel_index + 2 >= img.width * img.height * img.channels) {
                continue;
            }
            const r = img.data[pixel_index];
            const g = img.data[pixel_index + 1];
            const b = img.data[pixel_index + 2];
            const gray: u64 = @intFromFloat(@as(f32, @floatFromInt(r)) * 0.3 + @as(f32, @floatFromInt(g)) * 0.59 + @as(f32, @floatFromInt(b)) * 0.11);
            info.sum_brightness += gray;
            if (params.color) {
                info.sum_color[0] += r;
                info.sum_color[1] += g;
                info.sum_color[2] += b;
            }
            if (edge_result != null) {
                const edge_index = iy * img.width + ix;
                info.sum_mag += edge_result.?.magnitude[edge_index];
                info.sum_dir += edge_result.?.direction[edge_index];
            }
            info.pixel_count += 1;
        }
    }

    return info;
}

/// Select an ASCII character based on the brightness of a block
pub fn selectAsciiChar(block_info: BlockInfo, params: RenderParams) []const u8 {
    const avg_brightness: usize = @intCast(block_info.sum_brightness / block_info.pixel_count);
    const boosted_brightness: usize = @intFromFloat(@as(f32, @floatFromInt(avg_brightness)) * params.brightness_boost);
    const clamped_brightness = std.math.clamp(boosted_brightness, 0, 255);

    if (params.detect_edges) {
        const avg_mag: f32 = block_info.sum_mag / @as(f32, @floatFromInt(block_info.pixel_count));
        const avg_dir: f32 = block_info.sum_dir / @as(f32, @floatFromInt(block_info.pixel_count));
        if (getEdgeChar(avg_mag, avg_dir, params.threshold_disabled)) |ec| {
            return &[_]u8{ec};
        }
    }

    if (clamped_brightness == 0) return " ";

    const char_index = (clamped_brightness * params.ascii_chars.len) / 256;
    const selected_char = params.ascii_info[@min(char_index, params.ascii_info.len - 1)];
    return params.ascii_chars[selected_char.start .. selected_char.start + selected_char.len];
}

/// Calculate the average color of a block
fn calculateAverageColor(block_info: BlockInfo, params: RenderParams) [3]u8 {
    if (params.color) {
        var color = [3]u8{
            @intCast(block_info.sum_color[0] / block_info.pixel_count),
            @intCast(block_info.sum_color[1] / block_info.pixel_count),
            @intCast(block_info.sum_color[2] / block_info.pixel_count),
        };

        if (params.invert_color) {
            color[0] = 255 - color[0];
            color[1] = 255 - color[1];
            color[2] = 255 - color[2];
        }

        return color;
    } else {
        return .{ 255, 255, 255 };
    }
}

/// Convert an image block to ASCII representation
fn convertToAscii(
    img: []u8,
    w: usize,
    h: usize,
    x: usize,
    y: usize,
    ascii_char: []const u8,
    color: [3]u8,
    block_size: u8,
    color_enabled: bool,
    params: RenderParams,
) !void {
    const bm = &(try bitmap.getCharBitmap(ascii_char));
    const block_w = @min(block_size, w - x);
    const block_h = @min(block_size, img.len / (w * 3) - y);

    // Define colors
    const background_color = if (params.bg_color != null) params.bg_color.? else [3]u8{ 21, 9, 27 }; // Dark purple
    const text_color = if (params.fg_color != null) params.fg_color.? else [3]u8{ 211, 106, 111 }; // Light red

    var dy: usize = 0;
    while (dy < block_h) : (dy += 1) {
        var dx: usize = 0;
        while (dx < block_w) : (dx += 1) {
            const img_x = x + dx;
            const img_y = y + dy;

            if (img_x < w and img_y < h) {
                const idx = (img_y * w + img_x) * 3;
                const shift: u3 = @intCast(7 - dx);
                const bit: u8 = @as(u8, 1) << shift;
                if ((bm[dy] & bit) != 0) {
                    // Character pixel: use color
                    if (color_enabled) {
                        img[idx] = color[0];
                        img[idx + 1] = color[1];
                        img[idx + 2] = color[2];
                    } else {
                        img[idx] = text_color[0];
                        img[idx + 1] = text_color[1];
                        img[idx + 2] = text_color[2];
                    }
                } else {
                    // Not a character pixel: use background
                    if (color_enabled) {
                        img[idx] = 0;
                        img[idx + 1] = 0;
                        img[idx + 2] = 0;
                    } else {
                        img[idx] = background_color[0];
                        img[idx + 1] = background_color[1];
                        img[idx + 2] = background_color[2];
                    }
                }
            }
        }
    }
}

/// Find closest brightness value for dithering
fn findClosestBrightness(
    desired: u8,
    ascii_chars: []const u8,
    ascii_info: []const AsciiCharInfo,
) struct { u8, u32 } {
    const brightness = @as(u32, @intCast(desired));

    const char_index = (desired * ascii_chars.len) / 256;
    const selected_char = @min(char_index, ascii_info.len - 1);

    const quantized: u32 = @as(u32, @intCast(selected_char)) * (256 / @as(u32, @intCast(ascii_info.len)));

    return .{
        @as(u8, @intCast(quantized)),
        brightness - quantized,
    };
}

/// Floyd-Steinberg dithering algorithm
/// _ X 7
/// 3 5 1
/// (/16)
fn floydSteinberg(
    curr: []u32,
    next: []u32,
    x: u8,
    w: u8,
    quant_error: u32,
) void {
    if (x + 1 < w) {
        curr[x + 1] += (quant_error * 7) >> 4;
        next[x + 1] += (quant_error) >> 4;
    }
    if (x > 0) {
        next[x - 1] += (quant_error * 3) >> 4;
    }
    next[x] += (quant_error * 5) >> 4;
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
