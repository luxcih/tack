const std = @import("std");

const CLI = @import("CLI.zig");
const Command = @import("Command.zig");

const Invocation = @This();

/// The final CLI target reached by the invocation.
target: Target,
/// The path from the root CLI to the final target.
path: []const Target,

/// Positional arguments parsed from the invocation.
arguments: []const Argument,
/// Options parsed from the invocation.
options: []const Option,

/// Releases memory owned by the invocation.
pub fn deinit(self: *Invocation, allocator: std.mem.Allocator) void {
    allocator.free(self.path);
    allocator.free(self.arguments);
    allocator.free(self.options);
}

/// Returns the first parsed value for an argument, or null when absent.
pub fn argument(self: *const Invocation, name: []const u8) ?[]const u8 {
    for (self.arguments) |parsed_argument| {
        if (std.mem.eql(u8, parsed_argument.definition.name, name)) {
            return parsed_argument.value;
        }
    }

    return null;
}

/// Returns all parsed values belonging to an argument definition.
/// The returned slice must be freed with the provided allocator.
pub fn argument_values(
    self: *const Invocation,
    allocator: std.mem.Allocator,
    name: []const u8,
) ![]const []const u8 {
    var values = std.ArrayList([]const u8).empty;
    errdefer values.deinit(allocator);

    for (self.arguments) |parsed_argument| {
        if (std.mem.eql(u8, parsed_argument.definition.name, name)) {
            try values.append(allocator, parsed_argument.value);
        }
    }

    return values.toOwnedSlice(allocator);
}

/// Returns the parsed value of an option, or null when it was not provided.
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

/// Returns whether an option was provided.
pub fn has_option(self: *const Invocation, name: []const u8) bool {
    return self.option(name) != null;
}

/// Returns an option's parsed value or visible default.
pub fn option_value(self: *const Invocation, name: []const u8) ?[]const u8 {
    if (self.option(name)) |parsed_option| {
        return switch (parsed_option) {
            .flag => null,
            .value => |value| value,
        };
    }

    var path_index = self.path.len;
    while (path_index > 0) {
        path_index -= 1;
        const target = self.path[path_index];

        for (target.options()) |definition| {
            if (path_index + 1 < self.path.len and !definition.persistent) continue;

            if (definition.long) |long| {
                if (std.mem.eql(u8, long, name)) {
                    return definition.default;
                }
            }
        }
    }

    return null;
}

/// Identifies either the root CLI or a command in an invocation path.
pub const Target = union(enum) {
    cli: *const CLI,
    command: *const Command,

    /// Returns the positional arguments defined by this target.
    pub fn arguments(self: Target) []const Command.Argument {
        return switch (self) {
            .cli => |cli| cli.arguments,
            .command => |command| command.arguments,
        };
    }

    /// Returns the options defined by this target.
    pub fn options(self: Target) []const Command.Option {
        return switch (self) {
            .cli => |cli| cli.options,
            .command => |command| command.options,
        };
    }

};

/// A positional argument parsed from an invocation.
pub const Argument = struct {
    definition: *const Command.Argument,
    value: []const u8,
};

/// An option parsed from an invocation.
pub const Option = struct {
    definition: *const Command.Option,
    value: Value,

    /// The parsed representation of an option.
    pub const Value = union(Command.Option.Kind) {
        flag: bool,
        value: []const u8,
    };
};


test "persistent option defaults are inherited" {
    const Parser = @import("Parser.zig");

    const cli = CLI{
        .name = "app",
        .options = &.{.{
            .long = "format",
            .kind = .value,
            .default = "text",
            .persistent = true,
        }},
        .commands = &.{.{
            .name = "config",
            .commands = &.{.{ .name = "set" }},
        }},
    };

    var invocation = try Parser.parse(
        std.testing.allocator,
        &cli,
        &.{ "config", "set" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(
        "text",
        invocation.option_value("format").?,
    );
}
