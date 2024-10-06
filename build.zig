const std = @import("std");

const Test = struct {
    root_source_file: std.Build.LazyPath,

    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    mod: ?*std.Build.Module,
    mod_name: ?[]const u8,
};

fn add_test(b: *std.Build, step: *std.Build.Step, t: Test) !void {
    const test_case = b.addTest(.{
        .root_source_file = t.root_source_file,
        .target = t.target,
        .optimize = t.optimize,
    });

    if (t.mod) |mod|
        test_case.root_module.addImport(t.mod_name.?, mod);

    const run_test_case = b.addRunArtifact(test_case);

    step.dependOn(&run_test_case.step);
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mod = b.addModule("netlink", .{
        .root_source_file = .{
            .src_path = .{ .owner = b, .sub_path = "src/netlink.zig" },
        },
        .optimize = optimize,
        .target = target,
    });

    const test_step = b.step("test", "Run unit tests");
    {
        try add_test(b, test_step, .{
            .root_source_file = b.path("src/test/netlink.zig"),
            .optimize = optimize,
            .target = target,
            .mod = mod,
            .mod_name = "netlink",
        });
    }
}
