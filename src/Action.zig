const Invocation = @import("Invocation.zig");

/// The result returned by an action.
pub const Result = enum {
    /// Continue dispatching to the final action.
    continue_,
    /// Stop dispatching immediately.
    stop,
};

/// Runs during dispatch and controls whether it continues.
pub const Action = *const fn (*const Invocation) anyerror!Result;

/// Runs after the main action allows dispatch to complete.
pub const FinalAction = *const fn (*const Invocation) anyerror!void;
