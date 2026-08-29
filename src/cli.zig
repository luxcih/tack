const Argument = @import("argument.zig").Argument;
const Command = @import("command.zig").Command;
const Invocation = @import("invocation.zig").Invocation;
const Option = @import("option.zig").Option;

pub const CLI = struct {
    name: []const u8,
    description: ?[]const u8 = null,

    arguments: []const Argument = &.{},
    options: []const Option = &.{},
    commands: []const Command = &.{},

    action: ?Invocation.Action = null,

    pub fn dispatch(self: *const CLI, invocation: Invocation) !void {
        _ = self;

        if (invocation.action) |action| {
            try action(invocation);
        }
    }
};
