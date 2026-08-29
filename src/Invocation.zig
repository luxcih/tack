const std = @import("std");

const Action = @import("Action.zig");
const CLI = @import("CLI.zig");
const Command = @import("Command.zig");

const Invocation = @This();

target: Target,
path: []const Target,

arguments: []const Argument,
options: []const Option,

pub fn deinit(self: *Invocation, allocator: std.mem.Allocator) void {
    allocator.free(self.path);
    allocator.free(self.arguments);
    allocator.free(self.options);
}

pub fn argument(self: *const Invocation, name: []const u8) ?[]const u8 {
    for (self.arguments) |parsed_argument| {
        if (std.mem.eql(u8, parsed_argument.definition.name, name)) {
            return parsed_argument.value;
        }
    }

    return null;
}

pub fn option(self: *const Invocation, name: []const u8) ?Option.Value {
    for (self.options) |parsed_option| {
        if (parsed_option.definition.long) |long| {
            if (std.mem.eql(u8, long, name)) {
                return parsed_option.value;
            }
        }
    }

    return null;
}

pub fn has_option(self: *const Invocation, name: []const u8) bool {
    return self.option(name) != null;
}

pub fn option_value(self: *const Invocation, name: []const u8) ?[]const u8 {
    if (self.option(name)) |parsed_option| {
        return switch (parsed_option) {
            .flag => null,
            .value => |value| value,
        };
    }

    for (self.target.options()) |definition| {
        if (definition.long) |long| {
            if (std.mem.eql(u8, long, name)) {
                return definition.default;
            }
        }
    }

    return null;
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

    pub fn final_action(self: Target) ?Action {
        return switch (self) {
            .cli => |cli| cli.final_action,
            .command => |command| command.final_action,
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
