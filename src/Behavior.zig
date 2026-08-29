const Command = @import("Command.zig");
const Context = @import("Context.zig");
const Invocation = @import("Invocation.zig");

const Behavior = @This();

options: []const Command.Option = &.{},

handle: *const fn (
    context: *Context,
    invocation: *const Invocation,
) anyerror!Result,

pub const Result = enum {
    proceed,
    handled,
};
