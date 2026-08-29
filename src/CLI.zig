const std = @import("std");

const Action = @import("Action.zig").Action;
const ActionResult = @import("Action.zig").Result;
const FinalAction = @import("Action.zig").FinalAction;
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
final_action: ?FinalAction = null,

pub const ValidationError = error{
    RequiredArgumentAfterOptional,
    OptionHasNoName,
    FlagHasDefault,
    DuplicateLongOption,
    DuplicateShortOption,
    DuplicateCommand,
    DuplicateCommandName,
    DuplicateVisibleOption,
    RemainingArgumentNotLast,
};

pub fn validate(self: *const CLI) ValidationError!void {
    try validate_node(
        self.arguments,
        self.options,
        self.commands,
        &.{},
    );
}

fn validate_node(
    arguments: []const Command.Argument,
    options: []const Command.Option,
    commands: []const Command,
    inherited_persistent: []const Command.Option,
) ValidationError!void {
    try validate_arguments(arguments);
    try validate_options(options);
    try validate_visible_options(options, inherited_persistent);

    var persistent_count: usize = 0;
    for (options) |option| {
        if (option.persistent) persistent_count += 1;
    }

    if (persistent_count > 0) {
        // Validate descendants against each persistent option individually.
        for (options) |option| {
            if (!option.persistent) continue;
            for (commands) |command| {
                try validate_subtree_against_option(command, option);
            }
        }
    }

    for (commands, 0..) |command, index| {
        try validate_node(
            command.arguments,
            command.options,
            command.commands,
            options,
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

fn validate_subtree_against_option(
    command: Command,
    ancestor_option: Command.Option,
) ValidationError!void {
    for (command.options) |option| {
        if (options_conflict(option, ancestor_option)) {
            return error.DuplicateVisibleOption;
        }
    }

    for (command.commands) |child| {
        try validate_subtree_against_option(child, ancestor_option);
    }
}

fn validate_visible_options(
    options: []const Command.Option,
    inherited: []const Command.Option,
) ValidationError!void {
    for (options) |option| {
        for (inherited) |ancestor| {
            if (ancestor.persistent and options_conflict(option, ancestor)) {
                return error.DuplicateVisibleOption;
            }
        }
    }
}

fn validate_arguments(arguments: []const Command.Argument) ValidationError!void {
    var optional_seen = false;

    for (arguments, 0..) |argument, index| {
        if (argument.kind == .remaining and index + 1 != arguments.len) {
            return error.RemainingArgumentNotLast;
        }

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
        try action(invocation);
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


test "root action runs before root final action" {
    const Test = struct {
        var action_called = false;
        var final_called = false;

        fn action(_: *const Invocation) !ActionResult {
            action_called = true;
            return .continue_;
        }

        fn final(_: *const Invocation) !void {
            try std.testing.expect(action_called);
            final_called = true;
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

        fn final(_: *const Invocation) !void {
            final_called = true;
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

test "persistent options are inherited through descendants" {
    const cli = CLI{
        .name = "app",
        .options = &.{.{ .long = "verbose", .persistent = true }},
        .commands = &.{.{ .name = "config", .commands = &.{.{ .name = "set" }} }},
    };
    try cli.validate();
}

test "rejects descendant options that conflict with persistent options" {
    const cli = CLI{
        .name = "app",
        .options = &.{.{ .long = "verbose", .persistent = true }},
        .commands = &.{.{ .name = "config", .options = &.{.{ .long = "verbose" }} }},
    };
    try std.testing.expectError(error.DuplicateVisibleOption, cli.validate());
}
