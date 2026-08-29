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

pub fn run(
    self: *const CLI,
    allocator: std.mem.Allocator,
    args: []const []const u8,
) !void {
    var invocation = try Parser.parse(allocator, self, args);
    defer invocation.deinit(allocator);

    try self.dispatch(&invocation);
}

pub fn dispatch(self: *const CLI, invocation: *const Invocation) !void {
    _ = self;

    const action = invocation.target.action() orelse return;
    try action(invocation);
}
