const std = @import("std");
const bitmap = @import("bitmap.zig");

// -----------------------
// FONT BITMAP DATA
// -----------------------

// -----------------------
// CHARACTER SETS
// -----------------------

/// Different character sets for ASCII rendering
pub const DEFAULT_ASCII = " .:-=+*%@#";
pub const DEFAULT_BLOCK = " .:coPO?@█";
pub const FULL_CHARACTERS = " .-:=+iltIcsv1x%7aejorzfnuCJT3*69LYpqy25SbdgFGOVXkPhmw48AQDEHKUZR@B#NW0M";

/// Information about a character in the ASCII character set
pub const AsciiCharInfo = struct { start: usize, len: u8 };

/// Parameters for the ASCII renderer
pub const AsciiParams = struct {
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
    pub fn deinit(self: *AsciiParams, allocator: std.mem.Allocator) void {
        allocator.free(self.ascii_info);
    }
};

/// Available dithering options
pub const DitherType = enum { FloydSteinberg, None };

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

/// Create a new ASCII renderer configuration with default settings
pub fn createAsciiParams(allocator: std.mem.Allocator) !AsciiParams {
    const ascii_chars = DEFAULT_ASCII;
    const ascii_info = try initAsciiChars(allocator, ascii_chars);

    return AsciiParams{
        .ascii_chars = ascii_chars,
        .ascii_info = ascii_info,
        .color = true,
        .invert_color = false,
        .block_size = 8,
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

/// Select an ASCII character based on the brightness of a block
pub fn selectAsciiChar(block_info: BlockInfo, params: AsciiParams) []const u8 {
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

/// Convert an image block to ASCII representation
pub fn convertToAscii(
    img: []u8,
    w: usize,
    h: usize,
    x: usize,
    y: usize,
    ascii_char: []const u8,
    color: [3]u8,
    block_size: u8,
    color_enabled: bool,
    params: AsciiParams,
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

/// Temporarily holds information about a block of pixels
pub const BlockInfo = struct {
    sum_brightness: u64 = 0,
    sum_color: [3]u64 = .{ 0, 0, 0 },
    pixel_count: u64 = 0,
    sum_mag: f32 = 0,
    sum_dir: f32 = 0,
};

/// Calculate information about a block of pixels
pub fn calculateBlockInfo(
    img: Image,
    edge_result: ?EdgeData,
    x: usize,
    y: usize,
    out_w: usize,
    out_h: usize,
    params: AsciiParams,
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

/// Calculate the average color of a block
fn calculateAverageColor(block_info: BlockInfo, params: AsciiParams) [3]u8 {
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

/// Render an RGB image as ASCII art
pub fn renderToAscii(
    allocator: std.mem.Allocator,
    img: Image,
    params: AsciiParams,
) ![]u8 {
    // Safety checks
    if (img.width == 0 or img.height == 0) {
        return error.InvalidImageDimensions;
    }

    // Validate image data
    if (img.data.len < img.width * img.height * img.channels) {
        return error.InvalidImageData;
    }

    // Allocate output buffer
    var output_buffer = try allocator.alloc(u8, img.width * img.height * img.channels);
    errdefer allocator.free(output_buffer);

    // Initialize output buffer to zero
    @memset(output_buffer, 0);

    // Calculate output dimensions based on block size
    const out_w = @max((img.width / params.block_size) * params.block_size, 1);
    const out_h = @max((img.height / params.block_size) * params.block_size, 1);

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
                            output_buffer[out_idx] = params.fg_color[0];
                            output_buffer[out_idx + 1] = params.fg_color[1];
                            output_buffer[out_idx + 2] = params.fg_color[2];
                        }
                    } else {
                        // Not a character pixel: use background
                        if (params.color) {
                            output_buffer[out_idx] = 0;
                            output_buffer[out_idx + 1] = 0;
                            output_buffer[out_idx + 2] = 0;
                        } else {
                            output_buffer[out_idx] = params.bg_color[0];
                            output_buffer[out_idx + 1] = params.bg_color[1];
                            output_buffer[out_idx + 2] = params.bg_color[2];
                        }
                    }
                }
            }
        }
    }

    return output_buffer;
}
