const std = @import("std");
const Action = @import("../Action.zig");
const CLI = @import("../CLI.zig");
const Command = @import("../Command.zig");
const Invocation = @import("../Invocation.zig");

pub const option = Command.Option{
    .long = "help",
    .short = 'h',
    .persistent = true,
    .description = "Show help for the current command.",
};

pub const command = Command{
    .name = "help",
    .description = "Show help for a command.",
    .arguments = &.{
        .{
            .name = "command",
            .description = "Command path to show help for.",
            .required = false,
            .kind = .remaining,
        },
    },
};

pub fn action(invocation: *const Invocation) !Action.Result {
    if (invocation.has_option("help")) {
        try render_path(invocation.path);
        return .stop;
    }

    switch (invocation.target) {
        .command => |target| {
            if (target == &command) {
                const allocator = std.heap.page_allocator;
                const names = try invocation.argument_values(allocator, "command");
                defer allocator.free(names);

                const root = switch (invocation.path[0]) {
                    .cli => |cli| cli,
                    .command => unreachable,
                };

                const path = try resolve(allocator, root, names);
                defer allocator.free(path);

                try render_path(path);
                return .stop;
            }
        },
        .cli => {},
    }

    return .continue_;
}

pub fn render(invocation: *const Invocation) !void {
    try render_path(invocation.path);
}

pub fn resolve(
    allocator: std.mem.Allocator,
    cli: *const CLI,
    names: []const []const u8,
) ![]const Invocation.Target {
    var path = std.ArrayList(Invocation.Target).empty;
    errdefer path.deinit(allocator);

    try path.append(allocator, .{ .cli = cli });

    var commands = cli.commands;

    for (names) |name| {
        var found: ?*const Command = null;

        for (commands) |*candidate| {
            if (std.mem.eql(u8, candidate.name, name)) {
                found = candidate;
                break;
            }

            for (candidate.aliases) |alias| {
                if (std.mem.eql(u8, alias, name)) {
                    found = candidate;
                    break;
                }
            }

            if (found != null) break;
        }

        const target = found orelse return error.UnknownCommand;
        try path.append(allocator, .{ .command = target });
        commands = target.commands;
    }

    return path.toOwnedSlice(allocator);
}

pub fn render_path(path: []const Invocation.Target) !void {
    const target = path[path.len - 1];

    std.debug.print("Usage: ", .{});
    for (path, 0..) |path_target, index| {
        if (index != 0) std.debug.print(" ", .{});

        switch (path_target) {
            .cli => |cli| std.debug.print("{s}", .{cli.name}),
            .command => |command_target| std.debug.print("{s}", .{command_target.name}),
        }
    }

    if (target.arguments().len > 0) {
        std.debug.print(" [arguments]", .{});
    }

    var has_options = false;
    for (path, 0..) |path_target, index| {
        for (path_target.options()) |option_definition| {
            if (index + 1 == path.len or option_definition.persistent) {
                has_options = true;
                break;
            }
        }
        if (has_options) break;
    }

    if (has_options) {
        std.debug.print(" [options]", .{});
    }

    std.debug.print("\n", .{});

    if (target.arguments().len > 0) {
        std.debug.print("\nArguments:\n", .{});
        for (target.arguments()) |argument| {
            std.debug.print("  {s}", .{argument.name});
            if (argument.description) |description| {
                std.debug.print("  {s}", .{description});
            }
            std.debug.print("\n", .{});
        }
    }

    if (has_options) {
        std.debug.print("\nOptions:\n", .{});

        for (path, 0..) |path_target, index| {
            for (path_target.options()) |option_definition| {
                if (index + 1 < path.len and !option_definition.persistent) continue;

                std.debug.print("  ", .{});
                if (option_definition.short) |short| {
                    std.debug.print("-{c}", .{short});
                    if (option_definition.long != null) std.debug.print(", ", .{});
                }
                if (option_definition.long) |long| {
                    std.debug.print("--{s}", .{long});
                }
                if (option_definition.description) |description| {
                    std.debug.print("  {s}", .{description});
                }
                std.debug.print("\n", .{});
            }
        }
    }
}
