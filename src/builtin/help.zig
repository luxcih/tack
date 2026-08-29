const std = @import("std");
const Action = @import("../Action.zig");
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
    if (!invocation.has_option("help")) {
        return .continue_;
    }

    try render(invocation);
    return .stop;
}

pub fn render(invocation: *const Invocation) !void {
    const allocator = std.heap.page_allocator;
    const visible_options = try invocation.visible_options(allocator);
    defer allocator.free(visible_options);
    const target = invocation.getTarget();

    std.debug.print("Usage: ", .{});
    for (invocation.getPath(), 0..) |path_target, index| {
        if (index != 0) std.debug.print(" ", .{});

        switch (path_target) {
            .cli => |cli| std.debug.print("{s}", .{cli.name}),
            .command => |command_target| std.debug.print("{s}", .{command_target.name}),
        }
    }

    if (target.arguments().len > 0) {
        std.debug.print(" [arguments]", .{});
    }

    if (visible_options.len > 0) {
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

    if (visible_options.len > 0) {
        std.debug.print("\nOptions:\n", .{});
        for (visible_options) |option_pointer| {
            const option_definition = option_pointer;
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


