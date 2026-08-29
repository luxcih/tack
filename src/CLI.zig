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


pub const ValidationError = error{
    RequiredArgumentAfterOptional,
    OptionHasNoName,
    FlagHasDefault,
    DuplicateLongOption,
    DuplicateShortOption,
};

pub fn validate(self: *const CLI) ValidationError!void {
    var optional_seen = false;
    for (self.arguments) |argument| {
        if (!argument.required) optional_seen = true
        else if (optional_seen) return error.RequiredArgumentAfterOptional;
    }

    for (self.options, 0..) |option, index| {
        if (option.long == null and option.short == null) return error.OptionHasNoName;
        if (option.kind == .flag and option.default != null) return error.FlagHasDefault;

        for (self.options[index + 1 ..]) |other| {
            if (option.long) |long| if (other.long) |other_long| {
                if (std.mem.eql(u8, long, other_long)) return error.DuplicateLongOption;
            };
            if (option.short) |short| if (other.short) |other_short| {
                if (short == other_short) return error.DuplicateShortOption;
            };
        }
    }
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

    const action = invocation.target.action() orelse return;
    try action(invocation);
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
