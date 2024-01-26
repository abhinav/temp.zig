# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased
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

## 0.1.0

This is the first release of this library.

To use it, ensure that you have Zig 0.11 or newer,
and in a project with a build.zig.zon file,
run the following command:

```bash
zig fetch --save 'https://github.com/abhinav/temp.zig/archive/0.1.0.tar.gz'
```

See <https://abhinav.github.io/temp.zig> for documentation.
