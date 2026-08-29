const std = @import("std");

const Action = @import("Action.zig").Action;
const ActionResult = @import("Action.zig").Result;
const Command = @import("Command.zig");
const Invocation = @import("Invocation.zig");
const Parser = @import("Parser.zig");

const CLI = @This();

name: []const u8,
description: ?[]const u8 = null,

arguments: []const Command.Argument = &.{},
options: []const Command.Option = &.{},
persistent_options: []const Command.Option = &.{},
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
    DuplicateVisibleOption,
};

pub fn validate(self: *const CLI) ValidationError!void {
    try validate_node(
        self.arguments,
        self.options,
        self.persistent_options,
        self.commands,
    );
}

fn validate_node(
    arguments: []const Command.Argument,
    options: []const Command.Option,
    persistent_options: []const Command.Option,
    commands: []const Command,
) ValidationError!void {
    try validate_arguments(arguments);
    try validate_options(options);
    try validate_options(persistent_options);
    try validate_visible_options(options, persistent_options);

    for (commands, 0..) |command, index| {
        try validate_node(
            command.arguments,
            command.options,
            command.persistent_options,
            command.commands,
        );

        try validate_subtree_against_options(
            command,
            persistent_options,
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

fn validate_subtree_against_options(
    command: Command,
    ancestor_options: []const Command.Option,
) ValidationError!void {
    try validate_visible_options(command.options, ancestor_options);
    try validate_visible_options(command.persistent_options, ancestor_options);

    for (command.commands) |child| {
        try validate_subtree_against_options(child, ancestor_options);
    }
}

fn validate_visible_options(
    first: []const Command.Option,
    second: []const Command.Option,
) ValidationError!void {
    for (first) |option| {
        for (second) |other| {
            if (options_conflict(option, other)) {
                return error.DuplicateVisibleOption;
            }
        }
    }
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
    if (self.action) |action| {
        switch (try action(invocation)) {
            .continue_ => {},
            .stop => return,
        }
    }

    if (self.final_action) |action| {
        _ = try action(invocation);
    }
}

test "run parses and dispatches" {
    const Test = struct {
        var called = false;

        fn action(invocation: *const Invocation) !ActionResult {
            _ = invocation;
            called = true;
            return .continue_;
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


test "dispatches actions along the command path before the final action" {
    const Test = struct {
        var order: [4]u8 = undefined;
        var count: usize = 0;

        fn record(value: u8) void {
            order[count] = value;
            count += 1;
        }

        fn root(_: *const Invocation) !void {
            record(1);
        }

        fn config(_: *const Invocation) !void {
            record(2);
        }

        fn set(_: *const Invocation) !void {
            record(3);
        }

        fn final(_: *const Invocation) !void {
            record(4);
        }
    };

    Test.count = 0;

    const cli = CLI{
        .name = "app",
        .action = Test.root,
        .commands = &.{
            .{
                .name = "config",
                .action = Test.config,
                .commands = &.{
                    .{
                        .name = "set",
                        .action = Test.set,
                        .final_action = Test.final,
                    },
                },
            },
        },
    };

    var invocation = try Parser.parse(
        std.testing.allocator,
        &cli,
        &.{ "config", "set" },
    );
    defer invocation.deinit(std.testing.allocator);

    try cli.dispatch(&invocation);

    try std.testing.expectEqual(@as(usize, 4), Test.count);
    try std.testing.expectEqual(@as(u8, 1), Test.order[0]);
    try std.testing.expectEqual(@as(u8, 2), Test.order[1]);
    try std.testing.expectEqual(@as(u8, 3), Test.order[2]);
    try std.testing.expectEqual(@as(u8, 4), Test.order[3]);
}

test "runs only the reached target's final action" {
    const Test = struct {
        var root_called = false;
        var config_called = false;

        fn root(_: *const Invocation) !void {
            root_called = true;
        }

        fn config(_: *const Invocation) !void {
            config_called = true;
        }
    };

    Test.root_called = false;
    Test.config_called = false;

    const cli = CLI{
        .name = "app",
        .final_action = Test.root,
        .commands = &.{
            .{
                .name = "config",
                .final_action = Test.config,
            },
        },
    };

    var invocation = try Parser.parse(
        std.testing.allocator,
        &cli,
        &.{"config"},
    );
    defer invocation.deinit(std.testing.allocator);

    try cli.dispatch(&invocation);

    try std.testing.expect(!Test.root_called);
    try std.testing.expect(Test.config_called);
}

test "root action runs before root final action" {
    const Test = struct {
        var action_called = false;
        var final_called = false;

        fn action(_: *const Invocation) !ActionResult {
            action_called = true;
            return .continue_;
        }

        fn final(_: *const Invocation) !ActionResult {
            try std.testing.expect(action_called);
            final_called = true;
            return .continue_;
        }
    };

    Test.action_called = false;
    Test.final_called = false;

    const cli = CLI{
        .name = "app",
        .action = Test.action,
        .final_action = Test.final,
    };

    try cli.run(std.testing.allocator, &.{});

    try std.testing.expect(Test.action_called);
    try std.testing.expect(Test.final_called);
}


test "rejects a local option that conflicts with an inherited persistent option" {
    const cli = CLI{
        .name = "app",
        .persistent_options = &.{
            .{ .long = "verbose", .short = 'v' },
        },
        .commands = &.{
            .{
                .name = "config",
                .options = &.{
                    .{ .long = "verbose" },
                },
            },
        },
    };

    try std.testing.expectError(error.DuplicateVisibleOption, cli.validate());
}

test "rejects persistent options that conflict across a command path" {
    const cli = CLI{
        .name = "app",
        .persistent_options = &.{
            .{ .long = "verbose" },
        },
        .commands = &.{
            .{
                .name = "config",
                .persistent_options = &.{
                    .{ .long = "verbose" },
                },
            },
        },
    };

    try std.testing.expectError(error.DuplicateVisibleOption, cli.validate());
}

test "allows unrelated local options in different command branches" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "config",
                .options = &.{.{ .long = "force" }},
            },
            .{
                .name = "remove",
                .options = &.{.{ .long = "force" }},
            },
        },
    };

    try cli.validate();
}


test "stops dispatch when the action returns stop" {
    const Test = struct {
        var action_called = false;
        var final_called = false;

        fn action(_: *const Invocation) !ActionResult {
            action_called = true;
            return .stop;
        }

        fn final(_: *const Invocation) !ActionResult {
            final_called = true;
            return .continue_;
        }
    };

    Test.action_called = false;
    Test.final_called = false;

    const cli = CLI{
        .name = "app",
        .action = Test.action,
        .final_action = Test.final,
    };

    try cli.run(std.testing.allocator, &.{});

    try std.testing.expect(Test.action_called);
    try std.testing.expect(!Test.final_called);
}
