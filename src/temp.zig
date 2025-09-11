//! Cross-platform temporary files and directories.
//!
//! # Usage
//!
//! Use `TempDir.create` to create a new temporary directory,
//! or `TempFile.create` to create a new temporary file.
//! Both functions return a handle to the temporary artifact.
//! You must call the 'deinit' method to release resources
//! and delete the temporary artifact.
//!
//! ```
//! var tmp_dir = try TempDir.create(allocator, {});
//! defer tmp_dir.deinit();
//! ```
//!
//! Use the `pattern` option to change the name of the temporary resource.
//!
//! ```
//! var tmp_file = try TempFile.create(allocator, .{
//!    .pattern = "foo-*.txt",
//! });
//! defer tmp_file.deinit();
//! ```
//!
//! See `TempDir.CreateOptions` and `TempFile.CreateOptions`
//! for a full list of options.
//!
//! Use the `open` method to open the temporary artifact.
//! Be sure to close the handle when you're done with it.
//!
//! ```
//! var dir = try tmp_dir.open(.{});
//! defer dir.close();
//!
//! const file = try tmp_file.open(.{ .mode = .read_write });
//! defer file.close();
//! ```
//!
//! # Global temporary directory
//!
//! The `system_dir` function identifies the system-level global temporary directory.
//! On Unix-like systems, this is the `$TMPDIR` environment variable
//! or `/tmp` if `$TMPDIR` is not set.
//! On Windows, this comes from the `GetTempPathW` API,
//! which uses the `%TMP%`, `%TEMP%`, and `%USERPROFILE%` environment variables,
//! or the Windows directory if none of those are set.
//!
//! # Comparison with std.testing.tmpDir
//!
//! There are a few differences between `temp` and std.testing.tmpDir:
//!
//! - **Primary use case**:
//!   testing.tmpDir is intended for use in tests.
//!   `temp` is intended for use in both tests and production code.
//! - **Location**:
//!   testing.tmpDir always creates the temporary directory inside zig-cache/tmp.
//!   `temp` is able to use any parent directory,
//!   defaulting to the system-level global temporary directory.
//! - **File support**:
//!   testing.tmpDir supports only directories.
//!   `temp` supports both directories and files.
//! - **Retention support**:
//!   testing.tmpDir always deletes the temporary directory during cleanup.
//!   `temp` can be configured to retain temporary artifacts.
//! - **Naming pattern**:
//!   testing.tmpDir uses a fixed pattern for the temporary directory name.
//!   `temp` supports custom naming patterns.
//! - **System support**:
//!   testing.tmpDir is supported on all platforms that Zig supports.
//!   `temp` is supported only on Unix-like systems and Windows.

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const temp = @This();

// OS-specific errors.
const OSError = if (is_unix) error{} else error{Unexpected};

const is_unix = blk: {
    const tag = builtin.os.tag;
    if (tag.isDarwin() or tag.isBSD()) break :blk true;

    break :blk switch (tag) {
        .aix, .hurd, .linux, .plan9, .solaris => true,
        else => false,
    };
};

/// TempDir is a temporary directory that is deleted when deinit is called.
/// Construct one with `TempDir.create`.
pub const TempDir = struct {
    allocator: Allocator,

    /// Parent directory of the temporary directory.
    parent_dir: std.fs.Dir,
    should_close_parent: bool,

    /// Basename of the temporary directory inside `parent_dir`.
    basename: []const u8,

    /// Whether to keep the directory when the handle is closed.
    retain: bool,

    pub const CreateOptions = struct {
        /// Parent directory to create the temporary directory in.
        /// If null, the system-level global temporary directory is used.
        /// See `system_dir`.
        parent: ?std.fs.Dir = null,

        /// Pattern for the directory name.
        /// The last `*` in the pattern is replaced with a random string.
        /// If the pattern does not contain a `*`, one is appended.
        ///
        /// The pattern must not contain a path separator.
        pattern: []const u8 = "*",

        /// If true, don't delete the directory when the TempDir is closed.
        retain: bool = false,
    };

    pub const CreateError = error{
        /// A unique name could not be found after many attempts.
        /// This is a rare error that can occur if the system is under heavy load.
        /// Consider using a different pattern, or use a different parent directory.
        PathAlreadyExists,
    } || Allocator.Error || std.fs.File.OpenError || std.posix.MakeDirError || OSError;

    /// Creates a unique new directory,
    /// guaranteeing that the directory did not exist before the call.
    ///
    /// Use `opts.parent` to change the parent directory.
    /// If omitted, the system-level global temporary directory is used.
    ///
    /// Caller must call TempDir.deinit() to avoid leaking resources.
    ///
    /// Returns `CreateError.PathAlreadyExists` if a unique name could not be
    /// found after several attempts.
    pub fn create(alloc: Allocator, opts: CreateOptions) CreateError!TempDir {
        assert(std.mem.indexOf(u8, opts.pattern, std.fs.path.sep_str) == null); // must not contain path separator

        var parent_dir = opts.parent orelse try system_dir();
        const should_close_parent = opts.parent == null;
        errdefer if (should_close_parent) parent_dir.close(); // we own parent_dir

        var it = try NameGenerator.init(alloc, opts.pattern, 1000);
        defer it.deinit();

        while (try it.next()) |basename| {
            parent_dir.makeDir(basename) catch |err| {
                if (err == error.PathAlreadyExists) {
                    // Try again with a different random string.
                    continue;
                }
                return err;
            };

            return TempDir{
                .retain = opts.retain,
                .allocator = alloc,
                .basename = try alloc.dupe(u8, basename),
                .parent_dir = parent_dir,
                .should_close_parent = should_close_parent,
            };
        }

        return error.PathAlreadyExists;
    }

    /// Returns a handle to the temporary directory.
    /// The handle is a system resource and must be closed by the caller.
    pub fn open(self: *const TempDir, opts: std.fs.Dir.OpenOptions) std.fs.Dir.OpenError!std.fs.Dir {
        return self.parent_dir.openDir(self.basename, opts);
    }

    /// Frees up resources held by the TempDir.
    /// Deletes the temporary directory unless `retain` is true.
    pub fn deinit(self: *TempDir) void {
        if (!self.retain) {
            self.parent_dir.deleteTree(self.basename) catch {};
        }
        if (self.should_close_parent) {
            self.parent_dir.close();
        }
        self.allocator.free(self.basename);
    }
};

test TempDir {
    const alloc = std.testing.allocator;

    var tmp_dir = try TempDir.create(alloc, .{
        .pattern = "test-data-*",
    });
    defer tmp_dir.deinit();

    var dir = try tmp_dir.open(.{});
    defer dir.close();

    const f = try dir.createFile("foo.txt", .{});
    f.close();
}

/// Create a new temporary directory in the system's global temporary directory.
/// The directory is deleted when the returned handle is closed.
///
/// `pattern` specifies a naming pattern for the file.
/// The last `*` in the pattern is replaced with a random string.
///
/// For additional options, use `TempDir.create`.
pub fn create_dir(alloc: Allocator, pattern: []const u8) !TempDir {
    return try TempDir.create(alloc, .{ .pattern = pattern });
}

test create_dir {
    const alloc = std.testing.allocator;

    var tmp_dir = try temp.create_dir(alloc, "test-data-*");
    defer tmp_dir.deinit();

    var dir = try tmp_dir.open(.{});
    defer dir.close();

    const f = try dir.createFile("foo.txt", .{});
    f.close();
}

test "TempDir multiple threads" {
    if (builtin.single_threaded) {
        return error.SkipZigTest; // can't test concurrency
    }

    const NumIterations = 100;
    const NumWorkers = 10;

    const Worker = struct {
        fn run(alloc: Allocator, parent: std.fs.Dir) !void {
            for (0..NumIterations) |_| {
                var tmp_dir = try TempDir.create(alloc, .{
                    .parent = parent,
                    .pattern = "foo*",
                });
                tmp_dir.deinit();
            }
        }
    };

    const alloc = std.testing.allocator;

    var parent = std.testing.tmpDir(.{ .iterate = true });
    defer parent.cleanup();

    var workers: [NumWorkers]std.Thread = undefined;
    for (0..NumWorkers) |worker_idx| {
        // This will leak on error, but that's fine for a test.
        workers[worker_idx] = try std.Thread.spawn(.{}, Worker.run, .{ alloc, parent.dir });
    }

    for (0..NumWorkers) |i| workers[i].join();

    // Verify that everything was cleaned up after the workers exit.
    var it = parent.dir.iterate();
    var failed = false;
    while (try it.next()) |ent| {
        std.log.err("unexpected child: {s}\n", .{ent.name});
        failed = true;
    }
    try std.testing.expect(!failed); // saw unexpected files
}

/// TempFile is a temporary file that is deleted when the handle is closed.
/// Construct one with `TempFile.create`.
pub const TempFile = struct {
    allocator: Allocator,

    /// Parent directory of the temporary file.
    parent_dir: std.fs.Dir,
    should_close_parent: bool,

    /// Basename of the temporary file inside `parent_dir`.
    basename: []const u8,

    /// Whether to keep the file when the handle is closed.
    retain: bool,

    pub const CreateOptions = struct {
        /// Parent directory to create the temporary directory in.
        /// If null, the system-level global temporary directory is used.
        /// See `system_dir`.
        parent: ?std.fs.Dir = null,

        /// Pattern for the directory name.
        /// The last `*` in the pattern is replaced with a random string.
        /// If the pattern does not contain a `*`, one is appended.
        ///
        /// The pattern must not contain a path separator.
        pattern: []const u8 = "*",

        /// If true, don't delete the directory when the TempDir is closed.
        retain: bool = false,
    };

    pub const CreateError = error{PathAlreadyExists} ||
        Allocator.Error || std.fs.File.OpenError || OSError;

    /// Creates a unique new file in read-write mode,
    /// guaranteeing that the file did not exist before the call.
    ///
    /// Use `opts.parent` to change the parent directory.
    /// If omitted, the system-level global temporary directory is used.
    ///
    /// Caller must call TempFile.deinit() to avoid leaking resources.
    ///
    /// Returns error.PathAlreadyExists if a unique name could not be found
    /// after several attempts.
    pub fn create(alloc: Allocator, opts: CreateOptions) CreateError!TempFile {
        assert(std.mem.indexOf(u8, opts.pattern, std.fs.path.sep_str) == null); // must not contain path separator

        var parent_dir = opts.parent orelse try system_dir();
        const should_close_parent = opts.parent == null;
        errdefer if (should_close_parent) parent_dir.close(); // we own parent_dir

        var it = try NameGenerator.init(alloc, opts.pattern, 1000);
        defer it.deinit();

        while (try it.next()) |basename| {
            const file = parent_dir.createFile(basename, .{
                .exclusive = true,
            }) catch |err| {
                if (err == error.PathAlreadyExists) {
                    // Try again with a different random string.
                    continue;
                }
                return err;
            };
            file.close();

            return TempFile{
                .retain = opts.retain,
                .allocator = alloc,
                .basename = try alloc.dupe(u8, basename),
                .parent_dir = parent_dir,
                .should_close_parent = should_close_parent,
            };
        }

        return error.PathAlreadyExists;
    }

    /// Returns a handle to the temporary file.
    /// The handle is a system resource and must be closed by the caller.
    pub fn open(self: *const TempFile, opts: std.fs.File.OpenFlags) std.fs.File.OpenError!std.fs.File {
        return self.parent_dir.openFile(self.basename, opts);
    }

    /// Frees up resources held by the TempFile.
    /// Deletes the temporary file unless `retain` is true.
    pub fn deinit(self: *TempFile) void {
        if (!self.retain) {
            self.parent_dir.deleteFile(self.basename) catch {};
        }
        if (self.should_close_parent) {
            self.parent_dir.close();
        }
        self.allocator.free(self.basename);
    }
};

test TempFile {
    const alloc = std.testing.allocator;

    var tmp_file: TempFile = try TempFile.create(alloc, .{
        .pattern = "data*.txt",
    });
    defer tmp_file.deinit();

    var buf: [1024]u8 = undefined;

    var f: std.fs.File = try tmp_file.open(.{ .mode = .read_write });
    defer f.close();

    var writer = f.writer(&buf);
    var w = &writer.interface;
    try w.writeAll("hello\nworld\n");
    try w.flush();

    var reader = f.reader(&buf);
    var r = &reader.interface;

    const got = try r.allocRemaining(alloc, .unlimited);
    defer alloc.free(got);

    try std.testing.expectEqualStrings("hello\nworld\n", got);
}

/// Create a new temporary file in the system's global temporary directory.
/// The file is deleted when the returned handle is closed.
///
/// `pattern` specifies a naming pattern for the file.
/// The last `*` in the pattern is replaced with a random string.
///
/// For additional options, use `TempFile.create`.
pub fn create_file(alloc: Allocator, pattern: []const u8) !TempFile {
    return try TempFile.create(alloc, .{ .pattern = pattern });
}

test create_file {
    const alloc = std.testing.allocator;

    var tmp_file = try temp.create_file(alloc, "data*.txt");
    defer tmp_file.deinit();

    const f = try tmp_file.open(.{ .mode = .read_write });
    try f.writeAll("hello\nworld\n");
    f.close();
}

test "TempFile multiple threads" {
    if (builtin.single_threaded) {
        return error.SkipZigTest; // can't test concurrency
    }

    const NumIterations = 100;
    const NumWorkers = 10;

    const Worker = struct {
        fn run(alloc: Allocator, parent: std.fs.Dir) !void {
            for (0..NumIterations) |_| {
                var tmp_file = try TempFile.create(alloc, .{
                    .parent = parent,
                    .pattern = "foo*.txt",
                });
                tmp_file.deinit();
            }
        }
    };

    const alloc = std.testing.allocator;

    var parent = std.testing.tmpDir(.{ .iterate = true });
    defer parent.cleanup();

    var workers: [NumWorkers]std.Thread = undefined;
    for (0..NumWorkers) |worker_idx| {
        // This will leak on error, but that's fine for a test.
        workers[worker_idx] = try std.Thread.spawn(.{}, Worker.run, .{ alloc, parent.dir });
    }

    for (0..NumWorkers) |i| workers[i].join();

    // Verify that everything was cleaned up after the workers exit.
    var it = parent.dir.iterate();
    var failed = false;
    while (try it.next()) |ent| {
        std.log.err("unexpected child: {s}\n", .{ent.name});
        failed = true;
    }
    try std.testing.expect(!failed); // saw unexpected files
}

test "TempFile close without deleting" {
    const alloc = std.testing.allocator;

    var tmp_dir = try TempDir.create(alloc, .{});
    defer tmp_dir.deinit();

    var parent = try tmp_dir.open(.{});
    defer parent.close();

    var tmp_file = try TempFile.create(alloc, .{ .parent = parent });
    defer tmp_file.deinit();

    const f = try tmp_file.open(.{ .mode = .read_write });
    errdefer f.close();
    try f.writeAll("hello\n");
    f.close();

    _ = try parent.statFile(tmp_file.basename); // file should exist
}

/// Generates random names matching a pattern until a limit is reached.
const NameGenerator = struct {
    // TODO: Use random integer instead of fixed-width bytes.
    const random_bytes_count = 8;
    const random_basename_len = std.fs.base64_encoder.calcSize(random_bytes_count);

    allocator: Allocator,

    /// Part of the pattern before the `*`.
    prefix: []const u8,

    /// Part of the pattern after the `*`.
    suffix: []const u8,

    /// Buffer for the generated name. Reused across calls to `next`.
    basename: std.ArrayList(u8),

    attempt: usize,
    limit: usize,

    fn init(alloc: Allocator, pattern: []const u8, limit: usize) !NameGenerator {
        var prefix: []const u8 = undefined;
        var suffix: []const u8 = undefined;
        if (std.mem.lastIndexOf(u8, pattern, "*")) |i| {
            // "foo*bar" -> "foo" "bar"
            prefix = pattern[0..i];
            suffix = pattern[i + 1 ..];
        } else {
            // "foo" -> "foo" ""
            prefix = pattern;
            suffix = "";
        }

        const basename = try std.ArrayList(u8).initCapacity(alloc, prefix.len + suffix.len + random_basename_len);
        return NameGenerator{
            .allocator = alloc,
            .prefix = prefix,
            .suffix = suffix,
            .basename = basename,
            .attempt = 0,
            .limit = limit,
        };
    }

    fn deinit(self: *NameGenerator) void {
        self.basename.deinit(self.allocator);
    }

    /// Returns the next random basename matching the pattern.
    /// The slice is re-used across calls to `next`, so copy it if you need to keep it.
    ///
    /// Returns null if the limit is reached.
    fn next(self: *NameGenerator) !?[]const u8 {
        if (self.attempt >= self.limit) {
            return null;
        }
        defer self.attempt += 1;

        var random_bytes: [random_bytes_count]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);
        var rand_buffer: [random_basename_len]u8 = undefined;
        const rand_part = std.fs.base64_encoder.encode(&rand_buffer, random_bytes[0..]);

        self.basename.clearRetainingCapacity();
        try self.basename.appendSlice(self.allocator, self.prefix);
        try self.basename.appendSlice(self.allocator, rand_part);
        try self.basename.appendSlice(self.allocator, self.suffix);

        return self.basename.items;
    }

    test "empty pattern" {
        const alloc = std.testing.allocator;
        var it = try NameGenerator.init(alloc, "", 10);
        defer it.deinit();

        for (0..10) |_| {
            const name = try it.next();
            try std.testing.expect(name != null);
        }
    }

    test "no wildcard" {
        const alloc = std.testing.allocator;
        var it = try NameGenerator.init(alloc, "foo", 10);
        defer it.deinit();

        for (0..10) |_| {
            const name = try it.next() orelse @panic("expected name");
            errdefer std.debug.print("got: {s}\n", .{name});

            try std.testing.expectStringStartsWith(name, "foo");
        }
    }

    test "pattern" {
        const alloc = std.testing.allocator;
        var it = try NameGenerator.init(alloc, "foo*bar", 10);
        defer it.deinit();

        for (0..10) |_| {
            const name = try it.next() orelse @panic("expected name");
            errdefer std.debug.print("got: {s}\n", .{name});

            try std.testing.expectStringStartsWith(name, "foo");
            try std.testing.expectStringEndsWith(name, "bar");
        }
    }

    test "limit reached" {
        const alloc = std.testing.allocator;
        var it = try NameGenerator.init(alloc, "foo*", 1);
        defer it.deinit();

        try std.testing.expect(try it.next() != null);
        try std.testing.expect(try it.next() == null);
    }
};

pub const SystemDirError = std.fs.File.OpenError || OSError;

/// Returns a directory handle to the system-level global temporary directory.
/// The returned handle is a system resource and must be closed
/// to avoid leaking resources.
pub fn system_dir() SystemDirError!std.fs.Dir {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = system_dir_path(buf[0..]) catch |err| switch (err) {
        error.NameTooLong => unreachable, // violates MAX_PATH_BYTES
        else => return err,
    };
    return std.fs.openDirAbsolute(buf[0..n], .{});
}

test system_dir {
    var dir = try system_dir();
    defer dir.close();
}

pub const SystemDirPathError = error{NameTooLong} || OSError;

/// Writes the system-level global temporary directory to `buf`,
/// returning the length of the written string.
/// Returns error.NameTooLong if the path is longer than `buf.len`.
///
/// Typically, applications will want to create their own temporary directory
/// within this directory.
pub fn system_dir_path(buf: []u8) SystemDirPathError!usize {
    if (is_unix) {
        return system_dir_path_unix(buf);
    } else if (builtin.os.tag == .windows) {
        return windows.get_temp_path(buf);
    } else {
        @panic("unsupported operating system");
    }
}

fn system_dir_path_unix(buf: []u8) error{NameTooLong}!usize {
    const dir = std.posix.getenv("TMPDIR") orelse "/tmp";
    const dir_len = dir.len;
    if (dir_len > buf.len) {
        return error.NameTooLong;
    }

    @memcpy(buf[0..dir_len], dir);
    return dir_len;
}

test system_dir_path {
    var buf: [1024]u8 = undefined;
    const n = try system_dir_path(buf[0..]);

    const path = buf[0..n];
    try std.testing.expect(path.len > 0); // must be non-empty
}

pub const SystemDirPathAllocError = Allocator.Error || OSError;

/// Variant of `system_dir_path` that allocates a buffer.
/// The caller is responsible for freeing the buffer.
pub fn system_dir_path_alloc(alloc: Allocator) SystemDirPathAllocError![]const u8 {
    if (is_unix) {
        return system_dir_path_alloc_unix(alloc);
    } else if (builtin.os.tag == .windows) {
        return windows.get_temp_path_alloc(alloc);
    } else {
        @panic("unsupported operating system");
    }
}

fn system_dir_path_alloc_unix(alloc: Allocator) ![]const u8 {
    const dir = std.posix.getenv("TMPDIR") orelse "/tmp";
    return alloc.dupe(u8, dir);
}

test system_dir_path_alloc {
    const alloc = std.testing.allocator;

    const path = try system_dir_path_alloc(alloc);
    defer alloc.free(path);
    try std.testing.expect(path.len > 0); // must be non-empty

    // Calling again should return the same path.
    const path2 = try system_dir_path_alloc(alloc);
    defer alloc.free(path2);
    try std.testing.expectEqualStrings(path, path2);
}

/// Namespace for Windows-specific functionality.
const windows = struct {
    const kernel32 = std.os.windows.kernel32;
    const DWORD = std.os.windows.DWORD;

    /// > The maximum path of 32,767 characters is approximate, because the "\\?\"
    /// > prefix may be expanded to a longer string by the system at run time, and
    /// > this expansion applies to the total length.
    /// from https://docs.microsoft.com/en-us/windows/desktop/FileIO/naming-a-file#maximum-path-length-limitation
    pub const PATH_MAX_WIDE = 32767;

    /// Encodes the output of GetTempPathW to `buffer` as a UTF-8,
    /// returning the length of the written string.
    pub fn get_temp_path(buf: []u8) error{ NameTooLong, Unexpected }!usize {
        var wbuf: [PATH_MAX_WIDE]u16 = undefined;
        const n = try get_temp_path_w(wbuf.len, &wbuf);
        assert(n <= wbuf.len); // violates PATH_MAX_WIDE

        return try utf16le.to_utf8(buf, wbuf[0..n]);
    }

    /// Variant of `get_temp_path` that allocates a buffer.
    /// The caller is responsible for freeing the buffer.
    pub fn get_temp_path_alloc(alloc: Allocator) error{ OutOfMemory, Unexpected }![]const u8 {
        var wbuf: [PATH_MAX_WIDE]u16 = undefined;
        const n = try get_temp_path_w(wbuf.len, &wbuf);
        assert(n <= wbuf.len); // violates PATH_MAX_WIDE

        return try utf16le.to_utf8_alloc(alloc, wbuf[0..n]);
    }

    fn get_temp_path_w(wbuf_len: u32, wbuf: [*]u16) error{Unexpected}!u32 {
        const n = GetTempPathW(wbuf_len, wbuf);
        if (n == 0) {
            // > If the function fails, the return value is zero.
            // > To get extended error information, call GetLastError.
            // From https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettemppathw
            return std.os.windows.unexpectedError(kernel32.GetLastError());
        }
        return n;
    }

    extern "kernel32" fn GetTempPathW(
        nBufferLength: DWORD,
        lpBuffer: [*]u16,
    ) callconv(.winapi) DWORD;

    test get_temp_path {
        if (builtin.os.tag != .windows) return;

        var buffer: [PATH_MAX_WIDE]u8 = undefined;

        // Buffer too small.
        try std.testing.expectError(error.NameTooLong, get_temp_path(buffer[0..1]));

        // Large-enough buffer.
        const path_len = try get_temp_path(buffer[0..]);
        try std.testing.expect(path_len > 0); // must be non-empty
        const path = buffer[0..path_len];

        // Per the documentation for this API:
        //
        // > The returned string ends with a backslash, for example, "C:\TEMP\".
        try std.testing.expect(path[path.len - 1] == '\\');
    }

    test get_temp_path_alloc {
        if (builtin.os.tag != .windows) return;

        const alloc = std.testing.allocator;
        const path = try get_temp_path_alloc(alloc);
        defer alloc.free(path);

        try std.testing.expect(path.len > 0); // must be non-empty
        try std.testing.expect(path[path.len - 1] == '\\');
    }
};

/// Unsafe helpers for working with UTF-16LE.
/// These assume valid UTF-16LE, crashing if they encounter invalid unicode.
const utf16le = struct {
    /// Converts a UTF-16LE string to a UTF-8 string,
    /// returning the length of the written string.
    /// Fails with `NameTooLong` if the UTF-8 string would be longer than `buffer.len`.
    ///
    /// Assumes valid UTF-16LE, crashing if it encounters invalid unicode.
    fn to_utf8(buffer: []u8, utf16le_slice: []const u16) !usize {
        var end_index: usize = 0;
        var it = std.unicode.Utf16LeIterator.init(utf16le_slice);
        while (it.nextCodepoint() catch unreachable) |codepoint| {
            const seq_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            if (end_index + seq_len >= buffer.len)
                return error.NameTooLong;
            end_index += std.unicode.utf8Encode(codepoint, buffer[end_index..]) catch unreachable;
        }
        return end_index;
    }

    /// Variant of to_utf8 that allocates a buffer.
    /// The caller is responsible for freeing the buffer.
    ///
    /// Assumes valid UTF-16LE, crashing if it encounters invalid unicode.
    fn to_utf8_alloc(alloc: Allocator, utf16le_slice: []const u16) ![]const u8 {
        var result = try std.ArrayList(u8).initCapacity(alloc, utf16le_slice.len);
        errdefer result.deinit(alloc);

        var end_index: usize = 0;
        var it = std.unicode.Utf16LeIterator.init(utf16le_slice);
        while (it.nextCodepoint() catch unreachable) |codepoint| {
            const seq_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            try result.resize(alloc, result.items.len + seq_len);
            end_index += std.unicode.utf8Encode(codepoint, result.items[end_index..]) catch unreachable;
        }

        return result.toOwnedSlice(alloc);
    }
};

test {
    std.testing.refAllDecls(@This());
}
