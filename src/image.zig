const std = @import("std");
const tga = @import("tga.zig");

test "" {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Image);
}

/// Image defines a single image with 32-bit, non-alpha-premultiplied RGBA pixel data.
pub const Image = struct {
    allocator: std.mem.Allocator,
    pixels: []u8,
    width: usize,
    height: usize,

    /// init creates an empty image with the given dimensions.
    /// Asserts that width and height are > 0.
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !@This() {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);
        return @This(){
            .allocator = allocator,
            .width = width,
            .height = height,
            .pixels = try allocator.alloc(u8, width * height * 4),
        };
    }

    pub fn deinit(self: *const @This()) void {
        if (self.pixels.len > 0)
            self.allocator.free(self.pixels);
    }

    /// reinit re-initializes the image to the given size. This discards any existing pixel data.
    /// Asserts that width and height are > 0.
    pub fn reinit(self: *@This(), width: usize, height: usize) !void {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);
        self.deinit();
        self.width = width;
        self.height = height;
        self.pixels = try self.allocator.alloc(u8, width * height * 4);
    }

    /// readData reads image data from the encoded image data.
    pub fn readData(allocator: std.mem.Allocator, data: []const u8) !@This() {
        var stream = std.io.fixedBufferStream(data);
        return readStream(allocator, stream.reader());
    }

    /// readFilepath reads image data from the given file.
    pub fn readFilepath(allocator: std.mem.Allocator, filepath: []const u8) !@This() {
        const resolved = try std.fs.path.resolve(allocator, &.{filepath});
        defer allocator.free(resolved);

        var fd = try std.fs.openFileAbsolute(resolved, .{ .read = true, .write = false });
        defer fd.close();

        return readStream(allocator, fd.reader());
    }

    /// readStream reads image data from the given reader.
    pub fn readStream(allocator: std.mem.Allocator, reader: anytype) !@This() {
        var self = @This(){
            .allocator = allocator,
            .width = 0,
            .height = 0,
            .pixels = &.{},
        };
        try tga.decode(&self, reader);
        return self;
    }

    /// writeFilepath encodes the given image as TGA data and writes it to the given output file.
    /// This writes a 24- or 32-bit Truecolor image which is optionally RLE-compressed.
    /// The selected bit-depth depends on whether the input image is opaque or not.
    pub fn writeFilepath(self: *const Image, filepath: []const u8, compressed: bool) !void {
        const resolved = try std.fs.path.resolve(self.allocator, &.{filepath});
        defer self.allocator.free(resolved);

        var fd = try std.fs.createFileAbsolute(resolved, .{ .read = false, .truncate = true });
        defer fd.close();

        return self.writeStream(fd.writer(), compressed);
    }

    /// writeStream encodes the given image as TGA data and writes it to the given output stream.
    /// This writes a 24- or 32-bit Truecolor image which is optionally RLE-compressed.
    /// The selected bit-depth depends on whether the input image is opaque or not.
    pub fn writeStream(self: *const Image, writer: anytype, compressed: bool) !void {
        try tga.encode(writer, self, compressed);
    }

    /// get returns the pixel at the given coordinate.
    /// Asserts that the given coordinates are valid.
    pub inline fn get(self: *const @This(), x: usize, y: usize) []u8 {
        const index = self.offset(x, y);
        return self.pixels[index .. index + 4];
    }

    /// set sets the pixel at the given coordinate to the specified value.
    /// Asserts that the given coordinate is valid.
    /// Asserts that pixel.len >= 4.
    pub inline fn set(self: *const @This(), x: usize, y: usize, pixel: []u8) void {
        std.debug.assert(pixel.len >= 4);
        std.mem.copy(u8, self.pixels[self.offset(x, y)..], pixel[0..4]);
    }

    /// offset returns the pixel offset for the given x/y coordinate.
    /// Asserts that the given coordinate is valid.
    pub inline fn offset(self: *const @This(), x: usize, y: usize) usize {
        std.debug.assert(x < self.width);
        std.debug.assert(y < self.height);
        return y * self.width * 4 + x * 4;
    }

    /// isOpaque returns true if all pixels have an alpha value of 0xff.
    pub fn isOpaque(self: *const @This()) bool {
        var i: usize = 3;
        while (i < self.pixels.len) : (i += 4) {
            if (self.pixels[i] != 0xff)
                return false;
        }
        return true;
    }
};
