const std = @import("std");

const CLI = @import("CLI.zig");

const Context = @This();

allocator: std.mem.Allocator,
cli: *const CLI,
output: ?*std.Io.Writer = null,

pub const OutputError = error{
    OutputUnavailable,
};

pub fn writer(self: *Context) OutputError!*std.Io.Writer {
    return self.output orelse error.OutputUnavailable;
}
