const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .root_source_file = .{ .path = "src/c.zig" },
        .name = "json",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // _ = lib;
    // lib.emit_h = true;
    const exe = b.addExecutable(.{
        .name = "json",
        .root_source_file = .{ .path = "src/json.zig" },
        .target = target,
        .optimize = optimize,
    });
    const c_example = b.addExecutable(.{
        .name = "c_example",
        .root_source_file = .{ .path = "src/c/main.c" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    c_example.linkLibrary(lib);
    b.installArtifact(exe);
    b.installArtifact(c_example);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
