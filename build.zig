const std = @import("std");
const builtin = @import("builtin");
const zcc = @import("compile_commands");
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

const emcc_executable = "emcc";

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

    const chipmunk_dep = b.dependency("chipmunk2d", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.artifact("raylib");
    const chipmunk = chipmunk_dep.artifact("chipmunk");

    // create executable
    var exe: ?*std.Build.CompileStep = null;
    // emscripten library
    var lib: ?*std.Build.CompileStep = null;

    // initialize either lib or exe
    switch (target.getOsTag()) {
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
        step.linkLibrary(chipmunk);
    }

    switch (target.getOsTag()) {
        .wasi, .emscripten => {
            const emscripten_src = "build/emscripten/";
            const web_out_dir = b.pathJoin(&.{ b.install_prefix, "web" });
            const web_out_file = b.pathJoin(&.{ web_out_dir, "game.html" });

            if (b.sysroot == null) {
                std.log.err("\n\nUSAGE: Pass the '--sysroot \"$EMSDK/upstream/emscripten\"' flag.\n\n", .{});
                return;
            }

            const emscripten_include_flag = try includePrefixFlag(b.allocator, b.sysroot.?);

            lib.?.addCSourceFiles(&c_sources, &[_][]const u8{emscripten_include_flag});
            lib.?.defineCMacro("__EMSCRIPTEN__", null);
            lib.?.defineCMacro("PLATFORM_WEB", null);
            lib.?.addIncludePath(.{ .path = emscripten_src });

            const lib_output_include_flag = try includePrefixFlag(b.allocator, b.install_prefix);
            const shell_file = try std.fs.path.join(b.allocator, &.{ emscripten_src, "minshell.html" });
            const emcc_path = try std.fs.path.join(b.allocator, &.{ b.sysroot.?, "bin", emcc_executable });

            const command = &[_][]const u8{
                emcc_path,
                "-o",
                web_out_file,
                emscripten_src ++ "entry.c",
                "-I.",
                "-L.",
                "-I" ++ emscripten_src,
                lib_output_include_flag,
                "--shell-file",
                shell_file,
                "-DPLATFORM_WEB",
                "-sUSE_GLFW=3",
                "-sWASM=1",
                "-sALLOW_MEMORY_GROWTH=1",
                "-sWASM_MEM_MAX=512MB", //going higher than that seems not to work on iOS browsers ¯\_(ツ)_/¯
                "-sTOTAL_MEMORY=512MB",
                "-sABORTING_MALLOC=0",
                "-sASYNCIFY",
                "-sFORCE_FILESYSTEM=1",
                "-sASSERTIONS=1",
                "--memory-init-file",
                "0",
                "--preload-file",
                "assets",
                "--source-map-base",
                // "-sLLD_REPORT_UNDEFINED",
                "-sERROR_ON_UNDEFINED_SYMBOLS=0",
                // optimizations
                "-O3",
                // "-Os",
                // "-sUSE_PTHREADS=1",
                // "--profiling",
                // "-sTOTAL_STACK=128MB",
                // "-sMALLOC='emmalloc'",
                // "--no-entry",
                "-sEXPORTED_FUNCTIONS=['_malloc','_free','_main', '_emsc_main','_emsc_set_window_size']",
                "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap",
            };

            const emcc = b.addSystemCommand(command);

            // also statically link the remote libraries
            emcc.addArtifactArg(raylib);
            emcc.addArtifactArg(chipmunk);

            // also include it
            for (zcc.extractIncludeDirsFromCompileStep(b, lib.?)) |include_dir| {
                emcc.addArg(includeFlag(b.allocator, include_dir));
            }

            // add all the accumulated stuff to the command
            emcc.addArtifactArg(lib.?);
            emcc.step.dependOn(&lib.?.step);

            b.getInstallStep().dependOn(&emcc.step);

            std.fs.cwd().makePath(web_out_dir) catch {};

            std.log.info(
                \\
                \\Output files will be in {s}
                \\
                \\---
                \\cd {s}
                \\python -m http.server
                \\---
                \\
                \\building...
            ,
                .{ web_out_dir, web_out_dir },
            );
        },
        else => {
            try flags.appendSlice(b.allocator, if (optimize == .Debug) &debug_flags else &release_flags);

            exe.?.addCSourceFiles(&c_sources, flags.items);

            // always link libc
            for (targets.items) |t| {
                t.linkLibC();
            }

            // links and includes which are shared across platforms
            for (targets.items) |t| {
                t.addIncludePath("src/");
            }

            // platform-specific additions
            switch (target.getOsTag()) {
                .windows => {},
                .macos => {},
                .linux => {
                    for (targets.items) |t| {
                        t.addIncludePath("src/");
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
    switch (target.getOsTag()) {
        .windows => for (targets.items) |t| {
            unsetPkgConfig(t);
        },
        else => {},
    }

    zcc.createStep(b, "cdb", try targets.toOwnedSlice());
}

fn includePrefixFlag(ally: std.mem.Allocator, path: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(ally, "-I{s}/include", .{path});
}

fn includeFlag(ally: std.mem.Allocator, path: []const u8) []const u8 {
    return std.fmt.allocPrint(ally, "-I{s}", .{path}) catch @panic("OOM");
}

// Recursively unset all link objects' use_pkg_config setting
// fix for https://github.com/ziglang/zig/issues/14341
fn unsetPkgConfig(compile: *std.Build.Step.Compile) void {
    for (compile.link_objects.items) |*lo| {
        switch (lo.*) {
            .system_lib => |*system_lib| {
                system_lib.use_pkg_config = .no;
            },
            .other_step => |child_compile| unsetPkgConfig(child_compile),
            else => {},
        }
    }
}
