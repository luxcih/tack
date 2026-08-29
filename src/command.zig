const Argument = @import("argument.zig").Argument;
const Invocation = @import("invocation.zig").Invocation;
const Option = @import("option.zig").Option;

pub const Command = struct {
    name: []const u8,
    description: ?[]const u8 = null,

    aliases: []const []const u8 = &.{},

    arguments: []const Argument = &.{},
    options: []const Option = &.{},
    commands: []const Command = &.{},

    action: ?Invocation.Action = null,
};
