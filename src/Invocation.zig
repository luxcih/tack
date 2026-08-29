const Command = @import("Command.zig");

const Invocation = @This();

command: *const Command,

arguments: []const Argument,
options: []const Option,

pub const Argument = struct {
    definition: *const Command.Argument,
    value: []const u8,
};

pub const Option = struct {
    definition: *const Command.Option,
    value: Value,

    pub const Value = union(Command.Option.Kind) {
        flag: bool,
        value: []const u8,
    };
};
