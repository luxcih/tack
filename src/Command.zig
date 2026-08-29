const Command = @This();

/// The command name used on the command line.
name: []const u8,
/// An optional description of the command.
description: ?[]const u8 = null,

/// Alternative names that invoke this command.
aliases: []const []const u8 = &.{},

/// Positional arguments accepted by this command.
arguments: []const Argument = &.{},
/// Options accepted by this command.
options: []const Option = &.{},
/// Subcommands accepted by this command.
commands: []const Command = &.{},

/// Defines a positional command-line argument.
pub const Argument = struct {
    /// The argument name used in help output.
    name: []const u8,
    /// An optional description of the argument.
    description: ?[]const u8 = null,
    /// Whether the argument must be provided.
    required: bool = true,
    /// How the argument consumes command-line values.
    kind: Kind = .value,

    /// Determines how an argument consumes values.
    pub const Kind = enum {
        /// Consumes one value.
        value,
        /// Consumes all remaining positional values.
        remaining,
    };
};

/// Defines a command-line option.
pub const Option = struct {
    /// The long option name, without the leading dashes.
    long: ?[]const u8 = null,
    /// The short option name, without the leading dash.
    short: ?u8 = null,

    /// Whether the option is a flag or accepts a value.
    kind: Kind = .flag,
    /// The value used when the option is not provided.
    default: ?[]const u8 = null,
    /// Whether the option remains available to descendant commands.
    persistent: bool = false,

    /// An optional description of the option.
    description: ?[]const u8 = null,

    /// Determines how an option consumes values.
    pub const Kind = enum {
        /// A presence-only option.
        flag,
        /// An option that consumes one value.
        value,
    };
};
