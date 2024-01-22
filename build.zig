const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cover = b.option(bool, "test-cover", "Enable code coverage") orelse false;
    const cover_out = b.option(
        []const u8,
        "test-cover-out",
        "Output directory for coverage data",
    ) orelse b.pathFromRoot("cover");

    _ = if (@hasDecl(std.Build, "CreateModuleOptions"))
        // Zig 0.11
        b.addModule("temp", .{
            .source_file = .{ .path = "src/temp.zig" },
        })
    else
        // Zig 0.12
        b.addModule("temp", .{
            .root_source_file = .{ .path = "src/temp.zig" },
        });

    const lib = b.addStaticLibrary(.{
        .name = "temp",
        .root_source_file = .{ .path = "src/temp.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/temp.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const RunStep = if (@hasDecl(std, "build") and @hasDecl(std.build, "RunStep"))
        std.build.RunStep // Zig 0.11
    else
        std.Build.Step.Run // Zig 0.12
        ;

    if (cover) {
        run_unit_tests.has_side_effects = true;
        run_unit_tests.argv.insertSlice(0, &[_]RunStep.Arg{
            .{ .bytes = b.dupe("kcov") },
            .{ .bytes = b.fmt("--include-path={s}", .{b.pathFromRoot("src")}) },
            .{ .bytes = b.fmt("--strip-path={s}", .{b.pathFromRoot(".")}) },
            .{ .bytes = b.dupe(cover_out) },
        }) catch @panic("OOM");
    }

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const docs_step = b.step("docs", "Generate docs.");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = unit_tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
