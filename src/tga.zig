const std = @import("std");
const expect = std.testing.expect;
const Image = @import("image.zig").Image;

// ref: https://www.dca.fee.unicamp.br/~martino/disciplinas/ea978/tgaffs.pdf
// ref: http://www.paulbourke.net/dataformats/tga/

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Header);
    std.testing.refAllDecls(ImageType);
}

/// ImageType defines known TARGA image types.
const ImageType = enum(u8) {
    noData = 0,
    uncompressedColormapped = 1,
    uncompressedTruecolor = 2,
    uncompressedBlackAndWhite = 3,
    rleColormapped = 9,
    rleTruecolor = 10,
    rleBlackAndWhite = 11,
    compressedColormapped = 32, // huffman + delta + rle
    compressedColormapped4 = 33, // huffman + delta + rle -- 4-pass quadtree prcocess.
};

/// Header defines the contents of the file header.
const Header = packed struct {
    idLen: u8,
    colormapType: u8,
    imageType: ImageType,

    /// Index of the first color map entry. Index refers to the starting entry in loading the color map.
    /// Example: If you would have 1024 entries in the entire color map but you only need to store 72
    /// of those entries, this field allows you to start in the middle of the color-map (e.g., position 342).
    colormapOffset: u16,
    /// Total number of color map entries included.
    colormapLength: u16,
    /// Establishes the number of bits per entry. Typically 15, 16, 24 or 32-bit values are used.
    colormapDepth: u8,

    /// These bytes specify the absolute horizontal coordinate for the lower left corner of the image
    /// as it is positioned on a display device having an origin at the lower left of the screen
    /// (e.g., the TARGA series).
    imageX: u16,
    /// These bytes specify the absolute vertical coordinate for the lower left corner of the image
    /// as it is positioned on a display device having an origin at the lower left of the screen
    /// (e.g., the TARGA series).
    imageY: u16,

    /// This field specifies the width of the image in pixels.
    imageWidth: u16,
    /// This field specifies the height of the image in pixels.
    imageHeight: u16,
    /// This field indicates the number of bits per pixel. This number includes the Attribute or Alpha channel bits.
    /// Common values are 8, 16, 24 and 32 but other pixel depths could be used.
    imageDepth: u8,
    // Image descriptor fields.
    imageDescriptor: u8,
};

/// decode decodes a TGA image from the given reader into the specified image struct.
/// This supports 16-, 24- and 32-bit Truecolor images, optionally RLE-compressed.
pub fn decode(img: *Image, reader: anytype) !void {
    var buf: [18]u8 = undefined;
    if ((try reader.readAll(&buf)) < buf.len)
        return error.MissingHeader;

    var hdr = Header{
        .idLen = buf[0],
        .colormapType = buf[1],
        .imageType = @as(ImageType, @enumFromInt(buf[2])),
        .colormapOffset = @as(u16, @intCast(buf[3])) | (@as(u16, @intCast(buf[4])) << 8),
        .colormapLength = @as(u16, @intCast(buf[5])) | (@as(u16, @intCast(buf[6])) << 8),
        .colormapDepth = buf[7],
        .imageX = @as(u16, @intCast(buf[8])) | (@as(u16, @intCast(buf[9])) << 8),
        .imageY = @as(u16, @intCast(buf[10])) | (@as(u16, @intCast(buf[11])) << 8),
        .imageWidth = @as(u16, @intCast(buf[12])) | (@as(u16, @intCast(buf[13])) << 8),
        .imageHeight = @as(u16, @intCast(buf[14])) | (@as(u16, @intCast(buf[15])) << 8),
        .imageDepth = buf[16],
        .imageDescriptor = buf[17],
    };

    // std.debug.print("{}\n", .{hdr});

    switch (hdr.imageDepth) {
        16, 24, 32 => {},
        else => return error.UnsupportedBitdepth,
    }

    // Skip irrelevant stuff.
    const skip = @as(usize, @intCast(hdr.idLen)) + @as(usize, @intCast(hdr.colormapType)) *
        @as(usize, @intCast(hdr.colormapLength)) * @as(usize, @intCast(hdr.colormapDepth / 8));
    try reader.skipBytes(skip, .{});

    try img.reinit(@as(usize, @intCast(hdr.imageWidth)), @as(usize, @intCast(hdr.imageHeight)));
    errdefer img.deinit();

    switch (hdr.imageType) {
        .noData => {},
        .uncompressedTruecolor => try decodeUncompressedTruecolor(img, &hdr, reader),
        .rleTruecolor => try decodeRLETruecolor(img, &hdr, reader),
        else => return error.UnsupportedImageFormat,
    }
}

fn decodeUncompressedTruecolor(img: *Image, hdr: *const Header, reader: anytype) !void {
    const bytesPerPixel = @as(usize, @intCast(hdr.imageDepth)) / 8;
    var buffer: [4]u8 = undefined;

    var x: usize = 0;
    while (x < img.pixels.len) : (x += 4) {
        if ((try reader.readAll(buffer[0..bytesPerPixel])) < bytesPerPixel)
            return error.UnexpectedEOF;
        readPixel(img.pixels[x..], buffer[0..bytesPerPixel]);
    }
}

fn decodeRLETruecolor(img: *Image, hdr: *const Header, reader: anytype) !void {
    const bytesPerPixel = @as(usize, @intCast(hdr.imageDepth)) / 8;
    var buffer: [5]u8 = undefined;
    var dst: usize = 0;
    var i: usize = 0;

    while (dst < img.pixels.len) {
        const packetType = try reader.readByte();
        const runLength = @as(usize, @intCast(packetType & 0x7f)) + 1;

        if ((packetType & 0x80) > 0) { // RLE block
            if ((try reader.readAll(buffer[0..bytesPerPixel])) < bytesPerPixel)
                return error.UnexpectedEOF;

            i = 0;
            while (i < runLength) : (i += 1) {
                readPixel(img.pixels[dst..], buffer[0..bytesPerPixel]);
                dst += 4;
            }
        } else { // Normal block
            i = 0;
            while (i < runLength) : (i += 1) {
                if ((try reader.readAll(buffer[0..bytesPerPixel])) < bytesPerPixel)
                    return error.UnexpectedEOF;
                readPixel(img.pixels[dst..], buffer[0..bytesPerPixel]);
                dst += 4;
            }
        }
    }
}

/// readPixel copies the given source pixel to the destination buffer, while accounting for source bit depth.
/// Destination is always assumed to be 32-bit RGBA.
/// Asserts that dst.len >= 4.
fn readPixel(dst: []u8, src: []const u8) void {
    std.debug.assert(dst.len >= 4);
    switch (src.len) {
        2 => {
            dst[0] = (src[1] & 0x7c) << 1;
            dst[1] = ((src[1] & 0x03) << 6) | ((src[0] & 0xe0) >> 2);
            dst[2] = (src[0] & 0x1f) << 3;
            dst[3] = (src[1] & 0x80);
        },
        3 => {
            dst[0] = src[2];
            dst[1] = src[1];
            dst[2] = src[0];
            dst[3] = 0xff;
        },
        4 => {
            dst[0] = src[2];
            dst[1] = src[1];
            dst[2] = src[0];
            dst[3] = src[3];
        },
        else => {},
    }
}

/// encode encodes the given image as TGA data and writes it to the given output stream.
/// This writes a 24- or 32-bit Truecolor image which is optionally RLE-compressed.
/// The selected bit-depth depends on whether the input image is opaque or not.
pub fn encode(writer: anytype, img: *const Image, compress: bool) !void {
    const it = @intFromEnum(if (compress) ImageType.rleTruecolor else ImageType.uncompressedTruecolor);
    const wlo = @as(u8, @intCast(img.width & 0xff));
    const whi = @as(u8, @intCast((img.width >> 8) & 0xff));
    const hlo = @as(u8, @intCast(img.height & 0xff));
    const hhi = @as(u8, @intCast((img.height >> 8) & 0xff));
    const depth: u8 = if (img.isOpaque()) 24 else 32;

    // write the file header.
    try writer.writeAll(&[_]u8{ 0, 0, it, 0, 0, 0, 0, 0, 0, 0, 0, 0, wlo, whi, hlo, hhi, depth, 0 });

    // write pixel data.
    if (compress) {
        try encodeRLETruecolor(writer, img, depth);
    } else {
        try encodeUncompressedTruecolor(writer, img, depth);
    }

    // Write footer. Identifies the file as TGA 2.
    try writer.writeAll(&[_]u8{
        0, 0, 0, 0, // Extension area offset -- ignore it.
        0, 0, 0, 0, // Developer area offset -- ignore it.
        'T', 'R', 'U', 'E', 'V', 'I', 'S', 'I', 'O', 'N', '-', 'X', 'F', 'I', 'L', 'E', // signature string.
        '.', 0,
    });
}

fn encodeRLETruecolor(writer: anytype, img: *const Image, depth: u8) !void {
    const RawPacket = 0x00;
    const RLEPacket = 0x80;
    const bytesPerPixel = @as(usize, @intCast(depth)) / 8;
    const maxRunLen = @min(128, img.width);
    var packet: [5]u8 = undefined;
    var runLen: usize = 0;
    var i: usize = 0;

    while (i < img.pixels.len) : (i += runLen * 4) {
        runLen = getRunLength(img.pixels[i..], 4, maxRunLen);
        switch (runLen) {
            0 => return error.ZeroRunLength,
            1 => {
                // We don't want to store a full RLE packet for a single unique pixel. This would be rather inefficient.
                // Instead, find the number of consecutive instances of runLen 1 and encode them all as a single raw packet.
                var count: usize = 1;
                var ii: usize = i;
                while (getRunLength(img.pixels[ii..], 4, maxRunLen) == 1 and count < maxRunLen) : (ii += 4)
                    count += 1;

                try writer.writeByte(RawPacket | @as(u8, @intCast((count - 1) & 0x7f)));
                while (i <= ii) : (i += 4) {
                    packet[0] = img.pixels[i + 2];
                    packet[1] = img.pixels[i + 1];
                    packet[2] = img.pixels[i + 0];
                    packet[3] = img.pixels[i + 3];
                    try writer.writeAll(packet[0..bytesPerPixel]);
                }

                i -= 4;
            },
            else => {
                packet[0] = RLEPacket | @as(u8, @intCast((runLen - 1) & 0x7f));
                packet[1] = img.pixels[i + 2];
                packet[2] = img.pixels[i + 1];
                packet[3] = img.pixels[i + 0];
                packet[4] = img.pixels[i + 3];
                try writer.writeAll(packet[1 .. 1 + bytesPerPixel]);
            },
        }
    }
}

/// getRunLength returns the length of the next run of pixels in data.
/// The returned value will be at most max pixels.
fn getRunLength(data: []const u8, pixelSize: usize, max: usize) usize {
    if (data.len < pixelSize) return 0;

    const first = data[0..pixelSize];
    const maxi = max * pixelSize;

    var i: usize = pixelSize;
    while ((i < data.len) and (i <= maxi)) : (i += pixelSize) {
        if (!std.mem.eql(u8, first, data[i .. i + pixelSize]))
            break;
    }

    return i / pixelSize;
}

fn encodeUncompressedTruecolor(writer: anytype, img: *const Image, depth: u8) !void {
    const bytesPerPixel = @as(usize, @intCast(depth)) / 8;
    var pixel: [4]u8 = undefined;
    var i: usize = 0;
    while (i < img.pixels.len) : (i += 4) {
        pixel[0] = img.pixels[i + 2];
        pixel[1] = img.pixels[i + 1];
        pixel[2] = img.pixels[i + 0];
        pixel[3] = img.pixels[i + 3];
        try writer.writeAll(pixel[0..bytesPerPixel]);
    }
}

test "roundtrip" {
    const a = try Image.readFilepath(std.testing.allocator, "testdata/10x20-RLE0.tga");
    defer a.deinit();

    const b = try Image.readFilepath(std.testing.allocator, "testdata/10x20-RLE1.tga");
    defer b.deinit();

    try a.writeFilepath("testdata/10x20-RLE0-out.tga", false);
    try b.writeFilepath("testdata/10x20-RLE1-out.tga", true);

    const c = try Image.readFilepath(std.testing.allocator, "testdata/10x20-RLE0-out.tga");
    defer c.deinit();

    const d = try Image.readFilepath(std.testing.allocator, "testdata/10x20-RLE1-out.tga");
    defer d.deinit();

    try imgEql(&a, &b);
    try imgEql(&a, &c);
    try imgEql(&a, &d);
    try imgEql(&b, &c);
    try imgEql(&b, &d);
    try imgEql(&c, &d);
}

fn imgEql(a: *const Image, b: *const Image) !void {
    try expect(a.width == b.width);
    try expect(a.height == b.height);
    try expect(std.mem.eql(u8, a.pixels, b.pixels));
}
