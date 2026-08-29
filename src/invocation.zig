pub const Invocation = struct {
    pub const Action = *const fn (Invocation) anyerror!void;

    action: ?Action = null,
};
