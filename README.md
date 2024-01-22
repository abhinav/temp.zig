# 🗑️ temp.zig [![CI](https://github.com/abhinav/temp.zig/actions/workflows/ci.yml/badge.svg)](https://github.com/abhinav/temp.zig/actions/workflows/ci.yml) [![codecov](https://codecov.io/github/abhinav/temp.zig/graph/badge.svg?token=9CB5MRYCH5)](https://codecov.io/github/abhinav/temp.zig)

Cross-platform temporary files and directories in Zig.

# Features

- Temporary files and directories in any location
- Retain temporary artifacts on an opt-in basis
- Customize naming schemes

Supported operating systems:
Unix-like systems and Windows.

## API reference

Auto-generated API Reference for the library is available at
<https://abhinav.github.io/temp.zig/>.

Note that Zig's autodoc is currently in beta.
Some links may be broken in the generated website.

## Installation

Use `zig fetch --save` to pull a version of the library
into your build.zig.zon.
(This requires at least Zig 0.11.)

```bash
zig fetch --save "https://github.com/abhinav/temp.zig/archive/0.1.0.tar.gz"
```

Then, import the dependency in your build.zig:

```zig
pub fn build(b: *std.Build) void {
    // ...

    const temp = b.dependency("temp", .{
        .target = target,
        .optimize = optimize,
    });
```

And add it to the artifacts that need it:

```zig
    const exe = b.addExecutable(.{
        // ...
    });
    exe.root_module.addImport("temp", temp.module("temp"));
```

## License

This software is made available under the BSD3 license.
