const Invocation = @import("Invocation.zig");

pub const Action = *const fn (*const Invocation) anyerror!void;
