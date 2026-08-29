const Action = @import("Action.zig");
const Command = @import("Command.zig");
const Invocation = @import("Invocation.zig");

const CLI = @This();

name: []const u8,
description: ?[]const u8 = null,

arguments: []const Command.Argument = &.{},
options: []const Command.Option = &.{},
commands: []const Command = &.{},

action: ?Action = null,

pub fn dispatch(self: *const CLI, invocation: *const Invocation) !void {
    _ = self;

    const action = invocation.target.action() orelse return;
    try action(invocation);
}
