const std = @import("std");

const CLI = @import("CLI.zig");
const Command = @import("Command.zig");

pub const option = Command.Option{
    .long = "help",
    .short = 'h',
    .description = "Show help.",
};

pub fn render(writer: anytype, cli: *const CLI) !void {
    try render_definition(
        writer,
        cli.name,
        cli.description,
        cli.arguments,
        cli.options,
        cli.commands,
    );
}

pub fn render_command(
    writer: anytype,
    name: []const u8,
    command: *const Command,
) !void {
    try render_definition(
        writer,
        name,
        command.description,
        command.arguments,
        command.options,
        command.commands,
    );
}

fn render_definition(
    writer: anytype,
    name: []const u8,
    description: ?[]const u8,
    arguments: []const Command.Argument,
    options: []const Command.Option,
    commands: []const Command,
) !void {
    if (description) |text| {
        try writer.print("{s}\n\n", .{text});
    }

    try writer.print("Usage: {s}", .{name});

    for (arguments) |argument| {
        if (argument.required) {
            try writer.print(" <{s}>", .{argument.name});
        } else {
            try writer.print(" [{s}]", .{argument.name});
        }
    }

    if (options.len > 0) {
        try writer.writeAll(" [OPTIONS]");
    }

    if (commands.len > 0) {
        try writer.writeAll(" <COMMAND>");
    }

    try writer.writeAll("\n");

    if (arguments.len > 0) {
        try writer.writeAll("\nArguments:\n");
        for (arguments) |argument| {
            try writer.print("  {s}", .{argument.name});
            if (argument.description) |text| {
                try writer.print("  {s}", .{text});
            }
            try writer.writeAll("\n");
        }
    }

    if (options.len > 0) {
        try writer.writeAll("\nOptions:\n");
        for (options) |option| {
            try writer.writeAll("  ");

            if (option.short) |short| {
                try writer.print("-{c}", .{short});
                if (option.long != null) try writer.writeAll(", ");
            }

            if (option.long) |long| {
                try writer.print("--{s}", .{long});
            }

            if (option.kind == .value) {
                try writer.writeAll(" <VALUE>");
            }

            if (option.description) |text| {
                try writer.print("  {s}", .{text});
            }

            if (option.default) |value| {
                try writer.print(" (default: {s})", .{value});
            }

            try writer.writeAll("\n");
        }
    }

    if (commands.len > 0) {
        try writer.writeAll("\nCommands:\n");
        for (commands) |command| {
            try writer.print("  {s}", .{command.name});
            if (command.description) |text| {
                try writer.print("  {s}", .{text});
            }
            try writer.writeAll("\n");
        }
    }
}

test "renders basic CLI help" {
    const cli = CLI{
        .name = "tack",
        .description = "A command-line application.",
        .arguments = &.{
            .{ .name = "file", .description = "The input file." },
        },
        .options = &.{
            .{ .long = "verbose", .short = 'v', .description = "Show more output." },
        },
        .commands = &.{
            .{ .name = "build", .description = "Build the project." },
        },
    };

    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try render(stream.writer(), &cli);

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Usage: tack <file> [OPTIONS] <COMMAND>") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Arguments:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Commands:") != null);
}


test "renders command help" {
    const command = Command{
        .name = "build",
        .description = "Build the project.",
        .options = &.{
            .{ .long = "release", .short = 'r', .description = "Build in release mode." },
        },
    };

    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try render_command(stream.writer(), "app build", &command);

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Usage: app build [OPTIONS]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Build the project.") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "-r, --release") != null);
}
