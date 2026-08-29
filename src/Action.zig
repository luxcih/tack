const Invocation = @import("Invocation.zig");

pub const Result = enum {
    continue_,
    stop,
};

pub const Action = *const fn (*const Invocation) anyerror!Result;

/// Runs after the main action allows dispatch to complete.
pub const FinalAction = *const fn (*const Invocation) anyerror!void;
