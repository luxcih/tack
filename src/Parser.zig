const std = @import("std");

const CLI = @import("CLI.zig");
const Command = @import("Command.zig");

pub const Target = union(enum) {
    cli: *const CLI,
    command: *const Command,
};

pub const Resolution = struct {
    target: Target,
    index: usize,
};

pub fn resolve(
    cli: *const CLI,
    args: []const []const u8,
) Resolution {
    var target: Target = .{ .cli = cli };
    var commands = cli.commands;
    var index: usize = 0;

    while (index < args.len) {
        const command = findCommand(commands, args[index]) orelse break;

        target = .{ .command = command };
        commands = command.commands;
        index += 1;
    }

    return .{
        .target = target,
        .index = index,
    };
}

fn findCommand(
    commands: []const Command,
    arg: []const u8,
) ?*const Command {
    for (commands) |*command| {
        if (matches(command, arg)) {
            return command;
        }
    }

    return null;
}

fn matches(command: *const Command, arg: []const u8) bool {
    if (std.mem.eql(u8, command.name, arg)) {
        return true;
    }

    for (command.aliases) |alias| {
        if (std.mem.eql(u8, alias, arg)) {
            return true;
        }
    }

    return false;
}
