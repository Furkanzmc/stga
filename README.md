### stga

STGA (Simple-TGA) reads 16-, 24- and 32-bit Truecolor TGA images, 
and writes 24- and 32-bit Truecolor images.

Read and written images can optionally be RLE-compressed.


### Usage

Download the repository into your project's lib/vendor directory and add a reference
to it in your `build.zig` file.

```zig
    ...
    exe.addPackagePath("stga", "libs/stga/main.zig");
    ...
```

To use the library, add an import statement:

```zig
const tga = @import("stga");
```

To read an image from disk.
```zig
const img = try tga.Image.readFilepath(allocator, "file.tga");
defer img.deinit();
```

To read an image from stream.
```zig
const img = try tga.Image.readStream(allocator, myreader);
defer img.deinit();
```

To read an image from a byte buffer. This assumes the buffer holds a full TGA image file.
```zig
const img = try tga.Image.readData(allocator, mydata);
defer img.deinit();
```

To write image to disk -- optionally RLE compressed.
```zig
try img.writeFilepath("file.tga", true);
```

To write image to a stream -- optionally RLE compressed.
```zig
try img.writeStream(mywriter, true);
```


## License

Unless otherwise stated, this project and its contents are provided under a
3-Clause BSD license. Refer to the LICENSE file for its contents.