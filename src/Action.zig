const Invocation = @import("Invocation.zig");

pub const Result = enum {
    continue_,
    stop,
};

pub const Action = *const fn (*const Invocation) anyerror!Result;
