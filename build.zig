const std = @import("std");
const builtin = @import("builtin");
const zcc = @import("compile_commands");
const zemscripten = @import("zemscripten");
const app_name = "example_c_game";

const release_flags = [_][]const u8{
    "-std=c11",
    "-DNDEBUG",
    "-DRELEASE",
};

const debug_flags = [_][]const u8{
    "-std=c11",
    "-D_DEBUG",
};

const c_sources = [_][]const u8{
    "src/main.c",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var targets = std.ArrayList(*std.Build.Step.Compile){};
    var flags = std.ArrayList([]const u8){};

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });

    const box2d_dep = b.dependency("zig_box2d", .{
        .target = target,
        .optimize = optimize,
        // raylib will provide emsdk for everyone
        .emsdk_absolute_path = zemscripten.getEmsdkPathFromBuilder(raylib_dep.builder),
    });

    const raylib = raylib_dep.artifact("raylib");
    const box2d = box2d_dep.artifact("box2d");

    // create executable
    var exe: ?*std.Build.Step.Compile = null;
    // emscripten library
    var lib: ?*std.Build.Step.Compile = null;

    // initialize either lib or exe
    switch (target.result.os.tag) {
        .wasi, .emscripten => {
            lib = b.addLibrary(.{
                .name = app_name,
                .root_module = b.createModule(.{
                    .optimize = optimize,
                    .target = target,
                }),
            });
            try targets.append(b.allocator, lib.?);
        },
        else => {
            exe = b.addExecutable(.{
                .name = app_name,
                .root_module = b.createModule(.{
                    .optimize = optimize,
                    .target = target,
                }),
            });
            try targets.append(b.allocator, exe.?);
        },
    }

    for (targets.items) |step| {
        step.linkLibrary(raylib);
        step.linkLibrary(box2d);
    }

    switch (target.result.os.tag) {
        .wasi, .emscripten => {},
        else => {
            try flags.appendSlice(b.allocator, if (optimize == .Debug) &debug_flags else &release_flags);

            exe.?.addCSourceFiles(.{
                .root = b.path("."),
                .files = &c_sources,
                .flags = flags.items,
                .language = .c,
            });

            // always link libc
            for (targets.items) |t| {
                t.linkLibC();
            }

            // links and includes which are shared across platforms
            for (targets.items) |t| {
                t.addIncludePath(b.path("src/"));
            }

            // platform-specific additions
            switch (target.result.os.tag) {
                .windows => {},
                .macos => {},
                .linux => {
                    for (targets.items) |t| {
                        t.linkSystemLibrary("GL");
                        t.linkSystemLibrary("X11");
                    }
                },
                else => {},
            }

            const run_cmd = b.addRunArtifact(exe.?);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        },
    }

    for (targets.items) |t| {
        b.installArtifact(t);
    }

    // windows requires that no targets use pkg-config. of course.
    // because its a unix thing.
    // switch (target.result.os.tag) {
    //     .windows => for (targets.items) |t| {
    //         unsetPkgConfig(t);
    //     },
    //     else => {},
    // }

    _ = zcc.createStep(b, "cdb", try targets.toOwnedSlice(b.allocator));
}

fn includePrefixFlag(ally: std.mem.Allocator, path: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(ally, "-I{s}/include", .{path});
}

fn includeFlag(ally: std.mem.Allocator, path: []const u8) []const u8 {
    return std.fmt.allocPrint(ally, "-I{s}", .{path}) catch @panic("OOM");
}

// Recursively unset all link objects' use_pkg_config setting
// fix for https://github.com/ziglang/zig/issues/14341
// fn unsetPkgConfig(compile: *std.Build.Step.Compile) void {
//     for (compile) |*lo| {
//         switch (lo.*) {
//             .system_lib => |*system_lib| {
//                 system_lib.use_pkg_config = .no;
//             },
//             .other_step => |child_compile| unsetPkgConfig(child_compile),
//             else => {},
//         }
//     }
// }
