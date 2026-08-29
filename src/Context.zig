const std = @import("std");

const CLI = @import("CLI.zig");

const Context = @This();

allocator: std.mem.Allocator,
cli: *const CLI,
output: ?*std.Io.Writer = null,

/// Application-defined state available to actions and behaviors.
data: ?*anyopaque = null,

pub const OutputError = error{
    OutputUnavailable,
};

pub fn writer(self: *Context) OutputError!*std.Io.Writer {
    return self.output orelse error.OutputUnavailable;
}

pub fn dataAs(self: *const Context, comptime T: type) ?*T {
    const data = self.data orelse return null;
    return @ptrCast(@alignCast(data));
}
