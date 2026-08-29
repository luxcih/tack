const Action = @import("../Action.zig").Action;
const Command = @import("../Command.zig");

pub const option = Command.Option{
    .long = "help",
    .short = 'h',
    .persistent = true,
    .description = "Show help for the current command.",
};

// The command form is defined now; its behavior will be added with help rendering.
pub const command = Command{
    .name = "help",
    .description = "Show help for a command.",
};

// Reserved builtin action surface for the help mechanism.
pub const action: ?Action = null;
