# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased
### Removed
- Drop support for Zig 0.11. Only Zig 0.12 and newer are supported.

## 0.2.0 - 2024-01-26

This release contains a few breaking changes.
Primary among these is how to get a handle to the temporary file or directory.

Instead of `TempDir.dir` or `TempFile.file`, which held an open handle,
you must now call `TempDir.open` or `TempFile.open`.
Remember to close the returned handle separately from the `Temp{Dir, File}`.

```diff
-var dir = temp_dir.dir
+var dir = try temp_dir.open(.{});
+defer dir.close();
```

To prevent mixing up with with `std.fs.{Dir, File}.close()`,
the `Temp{Dir, File}` objects are now freed by the `deinit` method.

```diff
 var temp_dir = try TempDir.create(..);
-defer temp_dir.close();
+defer temp_dir.deinit();
```

### Added
- `TempDir`, `TempFile`: Add `open` methods to get an `std.fs.Dir` or
  `std.fs.File` for the temporary artifact.
- Add `create_file` and `create_dir` convenience functions
  for when `TempFile.create` and `TempDir.create` aren't necessary.

### Changed
- `TempDir`, `TempFile`: Replace `close` with `deinit`.

### Removed
- `TempDir`: Drop `dir` field. The `open` method should be used instead.
- `TempFile`: Drop `file` field. The `open` method should be used instead.

## 0.1.0 - 2024-01-21

This is the first release of this library.

To use it, ensure that you have Zig 0.11 or newer,
and in a project with a build.zig.zon file,
run the following command:

```bash
zig fetch --save 'https://github.com/abhinav/temp.zig/archive/0.1.0.tar.gz'
```

See <https://abhinav.github.io/temp.zig> for documentation.
