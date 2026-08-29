const std = @import("std");

const Action = @import("Action.zig");
const CLI = @import("CLI.zig");
const Command = @import("Command.zig");

const Invocation = @This();

target: Target,

arguments: []const Argument,
options: []const Option,

pub fn deinit(self: *Invocation, allocator: std.mem.Allocator) void {
    allocator.free(self.arguments);
    allocator.free(self.options);
}

pub const Target = union(enum) {
    cli: *const CLI,
    command: *const Command,

    pub fn arguments(self: Target) []const Command.Argument {
        return switch (self) {
            .cli => |cli| cli.arguments,
            .command => |command| command.arguments,
        };
    }

    pub fn options(self: Target) []const Command.Option {
        return switch (self) {
            .cli => |cli| cli.options,
            .command => |command| command.options,
        };
    }

    pub fn action(self: Target) ?Action {
        return switch (self) {
            .cli => |cli| cli.action,
            .command => |command| command.action,
        };
    }
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
