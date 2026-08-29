/// A composable command-line interface library for Zig.
pub const Action = @import("Action.zig").Action;
/// Controls whether dispatch continues after an action runs.
pub const ActionResult = @import("Action.zig").Result;
/// Runs after the main action allows dispatch to complete.
pub const FinalAction = @import("Action.zig").FinalAction;
/// Defines the root of a command-line interface.
pub const CLI = @import("CLI.zig");
/// Defines commands, arguments, and options.
pub const Command = @import("Command.zig");
/// Represents a parsed command-line invocation.
pub const Invocation = @import("Invocation.zig");
/// Parses command-line arguments into an invocation.
pub const Parser = @import("Parser.zig");
/// Built-in optional CLI features.
pub const builtin = @import("builtin/root.zig");
