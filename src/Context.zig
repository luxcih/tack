const std = @import("std");

const CLI = @import("CLI.zig");

const Context = @This();

allocator: std.mem.Allocator,
cli: *const CLI,
