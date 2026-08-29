const std = @import("std");

const CLI = @import("CLI.zig");
const Command = @import("Command.zig");
const Invocation = @import("Invocation.zig");

pub const Target = Invocation.Target;

/// Errors that can occur while parsing an invocation.
pub const Error = error{
    UnknownOption,
    MissingOptionValue,
    UnexpectedOptionValue,
    UnexpectedArgument,
    MissingArgument,
};

/// Parses command-line arguments into an invocation.
pub fn parse(
    allocator: std.mem.Allocator,
    cli: *const CLI,
    args: []const []const u8,
) !Invocation {
    var path = std.ArrayList(Target).empty;
    errdefer path.deinit(allocator);

    try path.append(allocator, .{ .cli = cli });

    var parsed_arguments = std.ArrayList(Invocation.Argument).empty;
    errdefer parsed_arguments.deinit(allocator);

    var parsed_options = std.ArrayList(Invocation.Option).empty;
    errdefer parsed_options.deinit(allocator);

    var commands = cli.commands;
    var argument_index: usize = 0;
    var options_ended = false;
    var index: usize = 0;

    while (index < args.len) {
        const arg = args[index];

        if (!options_ended and std.mem.eql(u8, arg, "--")) {
            options_ended = true;
            index += 1;
            continue;
        }

        if (!options_ended and std.mem.startsWith(u8, arg, "--")) {
            const option_arg = arg[2..];
            const name_end = std.mem.indexOfScalar(u8, option_arg, '=') orelse option_arg.len;
            const name = option_arg[0..name_end];
            const inline_value = if (name_end < option_arg.len)
                option_arg[name_end + 1 ..]
            else
                null;

            const option = findLongOption(path.items, name) orelse return error.UnknownOption;

            switch (option.kind) {
                .flag => {
                    if (inline_value != null) return error.UnexpectedOptionValue;

                    try parsed_options.append(allocator, .{
                        .definition = option,
                        .value = .{ .flag = true },
                    });
                    index += 1;
                },
                .value => {
                    const value = inline_value orelse blk: {
                        if (index + 1 >= args.len) return error.MissingOptionValue;
                        index += 1;
                        break :blk args[index];
                    };

                    try parsed_options.append(allocator, .{
                        .definition = option,
                        .value = .{ .value = value },
                    });
                    index += 1;
                },
            }
            continue;
        }

        if (!options_ended and arg.len > 1 and arg[0] == '-') {
            const short_args = arg[1..];
            var short_index: usize = 0;
            var consumed_next = false;

            while (short_index < short_args.len) {
                const short = short_args[short_index];
                const option = findShortOption(path.items, short) orelse return error.UnknownOption;

                switch (option.kind) {
                    .flag => {
                        try parsed_options.append(allocator, .{
                            .definition = option,
                            .value = .{ .flag = true },
                        });
                        short_index += 1;
                    },
                    .value => {
                        const attached_value = short_args[short_index + 1 ..];
                        const value = if (attached_value.len > 0)
                            attached_value
                        else blk: {
                            if (index + 1 >= args.len) return error.MissingOptionValue;
                            consumed_next = true;
                            break :blk args[index + 1];
                        };

                        try parsed_options.append(allocator, .{
                            .definition = option,
                            .value = .{ .value = value },
                        });
                        break;
                    },
                }
            }

            index += if (consumed_next) 2 else 1;
            continue;
        }

        if (!options_ended) {
            if (findCommand(commands, arg)) |command| {
                if (argument_index != 0) return error.UnexpectedArgument;

                try path.append(allocator, .{ .command = command });
                commands = command.commands;
                index += 1;
                continue;
            }
        }

        const target = path.items[path.items.len - 1];
        const definitions = target.arguments();

        if (argument_index >= definitions.len) return error.UnexpectedArgument;

        const definition = &definitions[argument_index];

        try parsed_arguments.append(allocator, .{
            .definition = definition,
            .value = arg,
        });

        if (definition.kind != .remaining) {
            argument_index += 1;
        }

        index += 1;
    }

    const target = path.items[path.items.len - 1];
    const definitions = target.arguments();

    for (definitions) |*definition| {
        if (!definition.required) continue;

        for (parsed_arguments.items) |parsed_argument| {
            if (parsed_argument.definition == definition) break;
        } else {
            return error.MissingArgument;
        }
    }

    return .{
        .target = target,
        .path = try path.toOwnedSlice(allocator),
        .arguments = try parsed_arguments.toOwnedSlice(allocator),
        .options = try parsed_options.toOwnedSlice(allocator),
    };
}

fn findCommand(
    commands: []const Command,
    arg: []const u8,
) ?*const Command {
    for (commands) |*command| {
        if (matches(command, arg)) {
            return command;
        }
    }

    return null;
}

fn findLongOption(
    path: []const Target,
    name: []const u8,
) ?*const Command.Option {
    var path_index = path.len;
    while (path_index > 0) {
        path_index -= 1;
        const target = path[path_index];

        for (target.options()) |*option| {
            if (path_index + 1 < path.len and !option.persistent) continue;

            if (option.long) |long| {
                if (std.mem.eql(u8, long, name)) return option;
            }
        }
    }

    return null;
}

fn findShortOption(
    path: []const Target,
    short: u8,
) ?*const Command.Option {
    var path_index = path.len;
    while (path_index > 0) {
        path_index -= 1;
        const target = path[path_index];

        for (target.options()) |*option| {
            if (path_index + 1 < path.len and !option.persistent) continue;

            if (option.short) |option_short| {
                if (option_short == short) return option;
            }
        }
    }

    return null;
}

fn matches(command: *const Command, arg: []const u8) bool {
    if (std.mem.eql(u8, command.name, arg)) {
        return true;
    }

    for (command.aliases) |alias| {
        if (std.mem.eql(u8, alias, arg)) {
            return true;
        }
    }

    return false;
}

test "parses positional arguments and options" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "add",
                .arguments = &.{
                    .{ .name = "name" },
                    .{ .name = "url" },
                },
                .options = &.{
                    .{ .long = "force", .short = 'f' },
                    .{ .long = "output", .short = 'o', .kind = .value },
                },
            },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "add", "origin", "https://example.com", "--force", "-o", "file.txt" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), invocation.arguments.len);
    try std.testing.expectEqualStrings("origin", invocation.arguments[0].value);
    try std.testing.expectEqualStrings("https://example.com", invocation.arguments[1].value);

    try std.testing.expectEqual(@as(usize, 2), invocation.options.len);

    switch (invocation.options[0].value) {
        .flag => |value| try std.testing.expect(value),
        .value => return error.TestUnexpectedResult,
    }

    switch (invocation.options[1].value) {
        .value => |value| try std.testing.expectEqualStrings("file.txt", value),
        .flag => return error.TestUnexpectedResult,
    }
}

test "rejects invalid invocations" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{
            .{ .name = "file" },
        },
        .options = &.{
            .{ .long = "output", .kind = .value },
        },
    };

    try std.testing.expectError(
        error.UnknownOption,
        parse(std.testing.allocator, &cli, &.{ "--unknown", "file.txt" }),
    );

    try std.testing.expectError(
        error.MissingOptionValue,
        parse(std.testing.allocator, &cli, &.{"--output"}),
    );

    try std.testing.expectError(
        error.MissingArgument,
        parse(std.testing.allocator, &cli, &.{}),
    );

    try std.testing.expectError(
        error.UnexpectedArgument,
        parse(std.testing.allocator, &cli, &.{ "one", "two" }),
    );
}

test "looks up invocation values by name" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{
            .{ .name = "file" },
        },
        .options = &.{
            .{ .long = "force", .short = 'f' },
            .{ .long = "output", .short = 'o', .kind = .value },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "input.txt", "--force", "--output", "result.txt" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("input.txt", invocation.argument("file").?);
    try std.testing.expect(invocation.argument("missing") == null);

    const force = invocation.option("force").?;
    switch (force) {
        .flag => |value| try std.testing.expect(value),
        .value => return error.TestUnexpectedResult,
    }

    const output = invocation.option("output").?;
    switch (output) {
        .value => |value| try std.testing.expectEqualStrings("result.txt", value),
        .flag => return error.TestUnexpectedResult,
    }

    try std.testing.expect(invocation.option("missing") == null);
}

test "provides convenient option helpers" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{ .long = "force", .short = 'f' },
            .{ .long = "output", .short = 'o', .kind = .value },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "--force", "--output", "result.txt" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("force"));
    try std.testing.expect(invocation.has_option("output"));
    try std.testing.expect(!invocation.has_option("missing"));

    try std.testing.expect(invocation.option_value("force") == null);
    try std.testing.expectEqualStrings("result.txt", invocation.option_value("output").?);
    try std.testing.expect(invocation.option_value("missing") == null);
}

test "allows optional arguments to be omitted" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{
            .{ .name = "file" },
            .{ .name = "destination", .required = false },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{"input.txt"},
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("input.txt", invocation.argument("file").?);
    try std.testing.expect(invocation.argument("destination") == null);
}

test "still requires required arguments" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{
            .{ .name = "file" },
            .{ .name = "destination", .required = false },
        },
    };

    try std.testing.expectError(
        error.MissingArgument,
        parse(std.testing.allocator, &cli, &.{}),
    );
}

test "uses default option values without marking options present" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{
                .long = "format",
                .kind = .value,
                .default = "text",
            },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{},
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(!invocation.has_option("format"));
    try std.testing.expectEqualStrings("text", invocation.option_value("format").?);
}

test "explicit option values override defaults" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{
                .long = "format",
                .kind = .value,
                .default = "text",
            },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "--format", "json" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("format"));
    try std.testing.expectEqualStrings("json", invocation.option_value("format").?);
}

test "stops parsing options after double dash" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{
            .{ .name = "value" },
        },
        .options = &.{
            .{ .long = "force", .short = 'f' },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "--", "--force" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), invocation.options.len);
    try std.testing.expectEqualStrings("--force", invocation.argument("value").?);
}

test "continues parsing positional arguments after double dash" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{
            .{ .name = "first" },
            .{ .name = "second" },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "one", "--", "-two" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("one", invocation.argument("first").?);
    try std.testing.expectEqualStrings("-two", invocation.argument("second").?);
}

test "parses inline long option values" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{ .long = "format", .kind = .value },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{"--format=json"},
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("json", invocation.option_value("format").?);
}

test "allows equals signs inside inline option values" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{ .long = "value", .kind = .value },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{"--value=one=two"},
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("one=two", invocation.option_value("value").?);
}

test "rejects inline values for flags" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{ .long = "force" },
        },
    };

    try std.testing.expectError(
        error.UnexpectedOptionValue,
        parse(std.testing.allocator, &cli, &.{"--force=true"}),
    );
}

test "parses combined short flags" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{ .long = "all", .short = 'a' },
            .{ .long = "brief", .short = 'b' },
            .{ .long = "count", .short = 'c' },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{"-abc"},
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("all"));
    try std.testing.expect(invocation.has_option("brief"));
    try std.testing.expect(invocation.has_option("count"));
}

test "allows a value option at the end of a short group" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{ .long = "verbose", .short = 'v' },
            .{ .long = "output", .short = 'o', .kind = .value },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "-vo", "file.txt" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("verbose"));
    try std.testing.expectEqualStrings("file.txt", invocation.option_value("output").?);
}

test "allows an attached value in a short option group" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{ .long = "verbose", .short = 'v' },
            .{ .long = "output", .short = 'o', .kind = .value },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{"-vofile.txt"},
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("verbose"));
    try std.testing.expectEqualStrings("file.txt", invocation.option_value("output").?);
}

test "inherits persistent options from the root CLI" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{ .long = "verbose", .short = 'v', .persistent = true },
        },
        .commands = &.{
            .{
                .name = "config",
                .commands = &.{
                    .{ .name = "set" },
                },
            },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "config", "set", "--verbose" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("verbose"));
}

test "inherits persistent options from nested commands" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "config",
                .options = &.{
                    .{ .long = "format", .kind = .value, .persistent = true },
                },
                .commands = &.{
                    .{ .name = "set" },
                },
            },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "config", "set", "--format", "json" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("json", invocation.option_value("format").?);
}

test "does not inherit normal options" {
    const cli = CLI{
        .name = "app",
        .options = &.{
            .{ .long = "verbose" },
        },
        .commands = &.{
            .{ .name = "config" },
        },
    };

    try std.testing.expectError(
        error.UnknownOption,
        parse(
            std.testing.allocator,
            &cli,
            &.{ "config", "--verbose" },
        ),
    );
}

test "allows persistent options before commands" {
    const cli = CLI{
        .name = "app",
        .options = &.{.{ .long = "verbose", .short = 'v', .persistent = true }},
        .commands = &.{.{ .name = "config", .commands = &.{.{ .name = "set" }} }},
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "--verbose", "config", "set" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("verbose"));
    switch (invocation.target) {
        .command => |command| try std.testing.expectEqualStrings("set", command.name),
        .cli => return error.TestUnexpectedResult,
    }
}

test "allows persistent options between commands" {
    const cli = CLI{
        .name = "app",
        .options = &.{.{ .long = "verbose", .short = 'v', .persistent = true }},
        .commands = &.{.{ .name = "config", .commands = &.{.{ .name = "set" }} }},
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "config", "-v", "set" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("verbose"));
    switch (invocation.target) {
        .command => |command| try std.testing.expectEqualStrings("set", command.name),
        .cli => return error.TestUnexpectedResult,
    }
}

test "allows persistent options after commands" {
    const cli = CLI{
        .name = "app",
        .options = &.{.{ .long = "verbose", .persistent = true }},
        .commands = &.{.{ .name = "config", .commands = &.{.{ .name = "set" }} }},
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "config", "set", "--verbose" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("verbose"));
}

test "commands cannot appear after positional arguments begin" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{.{ .name = "file" }},
        .commands = &.{.{ .name = "config" }},
    };

    try std.testing.expectError(
        error.UnexpectedArgument,
        parse(
            std.testing.allocator,
            &cli,
            &.{ "file.txt", "config" },
        ),
    );
}

test "options may appear after positional arguments" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{.{ .name = "file" }},
        .options = &.{.{ .long = "force" }},
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "file.txt", "--force" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.has_option("force"));
}

test "double dash ends option parsing" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{.{ .name = "value" }},
        .options = &.{.{ .long = "force" }},
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "--", "--force" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(!invocation.has_option("force"));
    try std.testing.expectEqualStrings(
        "--force",
        invocation.arguments[0].value,
    );
}

test "double dash prevents later command resolution" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{.{ .name = "value" }},
        .commands = &.{.{ .name = "config" }},
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "--", "config" },
    );
    defer invocation.deinit(std.testing.allocator);

    switch (invocation.target) {
        .cli => {},
        .command => return error.TestUnexpectedResult,
    }

    try std.testing.expectEqualStrings(
        "config",
        invocation.arguments[0].value,
    );
}

test "parent command receives arguments when it is the final target" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "remote",
                .arguments = &.{.{ .name = "name" }},
                .commands = &.{.{ .name = "add" }},
            },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "remote", "origin" },
    );
    defer invocation.deinit(std.testing.allocator);

    switch (invocation.target) {
        .command => |command| try std.testing.expectEqualStrings("remote", command.name),
        .cli => return error.TestUnexpectedResult,
    }

    try std.testing.expectEqualStrings("origin", invocation.arguments[0].value);
}

test "final nested command receives positional arguments" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "remote",
                .arguments = &.{.{ .name = "name" }},
                .commands = &.{
                    .{
                        .name = "add",
                        .arguments = &.{
                            .{ .name = "name" },
                            .{ .name = "url" },
                        },
                    },
                },
            },
        },
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "remote", "add", "origin", "https://example.com/repo" },
    );
    defer invocation.deinit(std.testing.allocator);

    switch (invocation.target) {
        .command => |command| try std.testing.expectEqualStrings("add", command.name),
        .cli => return error.TestUnexpectedResult,
    }

    try std.testing.expectEqual(@as(usize, 2), invocation.arguments.len);
    try std.testing.expectEqualStrings("origin", invocation.arguments[0].value);
    try std.testing.expectEqualStrings("https://example.com/repo", invocation.arguments[1].value);
}

test "arguments stop command traversal" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "remote",
                .arguments = &.{.{ .name = "name" }},
                .commands = &.{
                    .{ .name = "add" },
                },
            },
        },
    };

    try std.testing.expectError(
        error.UnexpectedArgument,
        parse(
            std.testing.allocator,
            &cli,
            &.{ "remote", "origin", "add" },
        ),
    );
}

test "parses remaining arguments" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{.{ .name = "files", .kind = .remaining }},
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "a.txt", "b.txt", "c.txt" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), invocation.arguments.len);
    for (invocation.arguments) |argument| {
        try std.testing.expectEqualStrings("files", argument.definition.name);
    }
}

test "remaining argument must be last" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{
            .{ .name = "files", .kind = .remaining },
            .{ .name = "destination" },
        },
    };

    try std.testing.expectError(error.RemainingArgumentNotLast, cli.validate());
}

test "required remaining arguments are satisfied by parsed values" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{.{ .name = "files", .kind = .remaining }},
    };

    var invocation = try parse(
        std.testing.allocator,
        &cli,
        &.{ "a.txt", "b.txt" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), invocation.arguments.len);
}

test "required remaining arguments cannot be omitted" {
    const cli = CLI{
        .name = "app",
        .arguments = &.{.{ .name = "files", .kind = .remaining }},
    };

    try std.testing.expectError(
        error.MissingArgument,
        parse(std.testing.allocator, &cli, &.{}),
    );
}
