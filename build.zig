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

    const temp = b.addModule("temp", .{
        .root_source_file = b.path("src/temp.zig"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "temp",
        .root_source_file = temp.root_source_file.?,
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_source_file = temp.root_source_file.?,
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");

    if (cover) {
        const run_coverage = std.Build.Step.Run.create(b, "Run coverage");
        run_coverage.addArg("kcov");
        run_coverage.addPrefixedDirectoryArg("--include-pattern=", b.path("src"));
        run_coverage.addPrefixedDirectoryArg("--strip-path=", b.path("."));
        run_coverage.addArg(cover_out);
        run_coverage.addArtifactArg(unit_tests);

        run_coverage.has_side_effects = true;

        test_step.dependOn(&run_coverage.step);
    } else {
        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    const docs_step = b.step("docs", "Generate docs.");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
