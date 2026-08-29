const CLI = @import("CLI.zig");
const Command = @import("Command.zig");

const Invocation = @This();

target: Target,

arguments: []const Argument,
options: []const Option,

pub const Target = union(enum) {
    cli: *const CLI,
    command: *const Command,
};

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
