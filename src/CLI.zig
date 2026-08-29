const std = @import("std");

const Action = @import("Action.zig");
const Command = @import("Command.zig");
const Invocation = @import("Invocation.zig");
const Parser = @import("Parser.zig");

const CLI = @This();

name: []const u8,
description: ?[]const u8 = null,

arguments: []const Command.Argument = &.{},
options: []const Command.Option = &.{},
commands: []const Command = &.{},
action: ?Action = null,
final_action: ?Action = null,

pub const ValidationError = error{
    RequiredArgumentAfterOptional,
    OptionHasNoName,
    FlagHasDefault,
    DuplicateLongOption,
    DuplicateShortOption,
    DuplicateCommand,
    DuplicateCommandName,
};

pub fn validate(self: *const CLI) ValidationError!void {
    try validate_definition(
        self.arguments,
        self.options,
        self.commands,
    );

}

fn validate_definition(
    arguments: []const Command.Argument,
    options: []const Command.Option,
    commands: []const Command,
) ValidationError!void {
    try validate_arguments(arguments);
    try validate_options(options);
    try validate_commands(commands);
}

fn validate_arguments(arguments: []const Command.Argument) ValidationError!void {
    var optional_seen = false;

    for (arguments) |argument| {
        if (!argument.required) {
            optional_seen = true;
        } else if (optional_seen) {
            return error.RequiredArgumentAfterOptional;
        }
    }
}

fn validate_options(options: []const Command.Option) ValidationError!void {
    for (options, 0..) |option, index| {
        if (option.long == null and option.short == null) {
            return error.OptionHasNoName;
        }

        if (option.kind == .flag and option.default != null) {
            return error.FlagHasDefault;
        }

        for (options[index + 1 ..]) |other| {
            if (option.long) |long| {
                if (other.long) |other_long| {
                    if (std.mem.eql(u8, long, other_long)) {
                        return error.DuplicateLongOption;
                    }
                }
            }

            if (option.short) |short| {
                if (other.short) |other_short| {
                    if (short == other_short) {
                        return error.DuplicateShortOption;
                    }
                }
            }
        }
    }
}

fn options_conflict(
    first: Command.Option,
    second: Command.Option,
) bool {
    if (first.long) |long| {
        if (second.long) |other_long| {
            if (std.mem.eql(u8, long, other_long)) return true;
        }
    }

    if (first.short) |short| {
        if (second.short) |other_short| {
            if (short == other_short) return true;
        }
    }

    return false;
}

fn validate_commands(commands: []const Command) ValidationError!void {
    for (commands, 0..) |command, index| {
        try validate_definition(
            command.arguments,
            command.options,
            command.commands,
        );

        for (commands[index + 1 ..]) |other| {
            if (std.mem.eql(u8, command.name, other.name)) {
                return error.DuplicateCommand;
            }

            if (command_name_conflicts(command, other)) {
                return error.DuplicateCommandName;
            }
        }
    }
}

fn command_name_conflicts(first: Command, second: Command) bool {
    for (first.aliases) |alias| {
        if (std.mem.eql(u8, alias, second.name)) return true;

        for (second.aliases) |other_alias| {
            if (std.mem.eql(u8, alias, other_alias)) return true;
        }
    }

    for (second.aliases) |alias| {
        if (std.mem.eql(u8, first.name, alias)) return true;
    }

    return false;
}

pub fn run(
    self: *const CLI,
    allocator: std.mem.Allocator,
    args: []const []const u8,
) !void {
    try self.validate();

    var invocation = try Parser.parse(allocator, self, args);
    defer invocation.deinit(allocator);

    try self.dispatch(&invocation);
}

pub fn dispatch(self: *const CLI, invocation: *const Invocation) !void {
    _ = self;

    if (invocation.target.action()) |action| {
        try action(invocation);
    }

    if (invocation.target.final_action()) |action| {
        try action(invocation);
    }
}

test "dispatches the target action" {
    const Test = struct {
        var called = false;

        fn action(invocation: *const Invocation) !void {
            _ = invocation;
            called = true;
        }
    };

    Test.called = false;

    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "hello",
                .action = Test.action,
            },
        },
    };

    var invocation = try Parser.parse(
        std.testing.allocator,
        &cli,
        &.{"hello"},
    );
    defer invocation.deinit(std.testing.allocator);

    try cli.dispatch(&invocation);
    try std.testing.expect(Test.called);
}

test "does nothing when the target has no action" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{ .name = "group" },
        },
    };

    var invocation = try Parser.parse(
        std.testing.allocator,
        &cli,
        &.{"group"},
    );
    defer invocation.deinit(std.testing.allocator);

    try cli.dispatch(&invocation);
}

test "run parses and dispatches" {
    const Test = struct {
        var called = false;

        fn action(invocation: *const Invocation) !void {
            _ = invocation;
            called = true;
        }
    };

    Test.called = false;

    const cli = CLI{
        .name = "app",
        .action = Test.action,
    };

    try cli.run(std.testing.allocator, &.{});
    try std.testing.expect(Test.called);
}


test "run validates before parsing" {
    const cli = CLI{
        .name = "app",
        .options = &.{.{}},
    };

    try std.testing.expectError(
        error.OptionHasNoName,
        cli.run(std.testing.allocator, &.{}),
    );
}


test "rejects duplicate command names" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{ .name = "build" },
            .{ .name = "build" },
        },
    };

    try std.testing.expectError(error.DuplicateCommand, cli.validate());
}

test "rejects command aliases that conflict with names" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{ .name = "build", .aliases = &.{"b"} },
            .{ .name = "bench", .aliases = &.{"build"} },
        },
    };

    try std.testing.expectError(error.DuplicateCommandName, cli.validate());
}

test "validates nested commands recursively" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "config",
                .commands = &.{
                    .{
                        .name = "set",
                        .options = &.{
                            .{ .long = "value" },
                            .{ .long = "value" },
                        },
                    },
                },
            },
        },
    };

    try std.testing.expectError(error.DuplicateLongOption, cli.validate());
}
