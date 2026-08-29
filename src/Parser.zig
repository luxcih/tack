const std = @import("std");

const CLI = @import("CLI.zig");
const Command = @import("Command.zig");
const Invocation = @import("Invocation.zig");

pub const Target = Invocation.Target;

pub const Resolution = struct {
    target: Target,
    index: usize,
};

pub const Error = error{
    UnknownOption,
    MissingOptionValue,
    UnexpectedArgument,
    MissingArgument,
};

pub fn parse(
    allocator: std.mem.Allocator,
    cli: *const CLI,
    args: []const []const u8,
) !Invocation {
    const resolution = resolve(cli, args);
    const target = resolution.target;

    var parsed_arguments = std.ArrayList(Invocation.Argument).empty;
    errdefer parsed_arguments.deinit(allocator);

    var parsed_options = std.ArrayList(Invocation.Option).empty;
    errdefer parsed_options.deinit(allocator);

    const definitions = target.arguments();
    const options = target.options();

    var index = resolution.index;
    var argument_index: usize = 0;

    while (index < args.len) {
        const arg = args[index];

        if (std.mem.startsWith(u8, arg, "--")) {
            const name = arg[2..];
            const option = findLongOption(options, name) orelse return error.UnknownOption;

            switch (option.kind) {
                .flag => {
                    try parsed_options.append(allocator, .{
                        .definition = option,
                        .value = .{ .flag = true },
                    });
                    index += 1;
                },
                .value => {
                    if (index + 1 >= args.len) {
                        return error.MissingOptionValue;
                    }

                    try parsed_options.append(allocator, .{
                        .definition = option,
                        .value = .{ .value = args[index + 1] },
                    });
                    index += 2;
                },
            }
        } else if (arg.len > 1 and arg[0] == '-') {
            const option = findShortOption(options, arg[1]) orelse return error.UnknownOption;

            if (arg.len != 2) {
                return error.UnknownOption;
            }

            switch (option.kind) {
                .flag => {
                    try parsed_options.append(allocator, .{
                        .definition = option,
                        .value = .{ .flag = true },
                    });
                    index += 1;
                },
                .value => {
                    if (index + 1 >= args.len) {
                        return error.MissingOptionValue;
                    }

                    try parsed_options.append(allocator, .{
                        .definition = option,
                        .value = .{ .value = args[index + 1] },
                    });
                    index += 2;
                },
            }
        } else {
            if (argument_index >= definitions.len) {
                return error.UnexpectedArgument;
            }

            try parsed_arguments.append(allocator, .{
                .definition = &definitions[argument_index],
                .value = arg,
            });

            argument_index += 1;
            index += 1;
        }
    }

    for (definitions[argument_index..]) |definition| {
        if (definition.required) {
            return error.MissingArgument;
        }
    }

    return .{
        .target = target,
        .arguments = try parsed_arguments.toOwnedSlice(allocator),
        .options = try parsed_options.toOwnedSlice(allocator),
    };
}

pub fn resolve(
    cli: *const CLI,
    args: []const []const u8,
) Resolution {
    var target: Target = .{ .cli = cli };
    var commands = cli.commands;
    var index: usize = 0;

    while (index < args.len) {
        const command = findCommand(commands, args[index]) orelse break;

        target = .{ .command = command };
        commands = command.commands;
        index += 1;
    }

    return .{
        .target = target,
        .index = index,
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
    options: []const Command.Option,
    name: []const u8,
) ?*const Command.Option {
    for (options) |*option| {
        if (option.long) |long| {
            if (std.mem.eql(u8, long, name)) {
                return option;
            }
        }
    }

    return null;
}

fn findShortOption(
    options: []const Command.Option,
    short: u8,
) ?*const Command.Option {
    for (options) |*option| {
        if (option.short) |option_short| {
            if (option_short == short) {
                return option;
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


test "resolves nested commands" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "remote",
                .commands = &.{
                    .{ .name = "add" },
                },
            },
        },
    };

    const resolution = resolve(&cli, &.{ "remote", "add", "origin" });

    try std.testing.expectEqual(@as(usize, 2), resolution.index);

    switch (resolution.target) {
        .command => |command| try std.testing.expectEqualStrings("add", command.name),
        .cli => return error.TestUnexpectedResult,
    }
}

test "resolves command aliases" {
    const cli = CLI{
        .name = "app",
        .commands = &.{
            .{
                .name = "remove",
                .aliases = &.{ "rm" },
            },
        },
    };

    const resolution = resolve(&cli, &.{"rm"});

    switch (resolution.target) {
        .command => |command| try std.testing.expectEqualStrings("remove", command.name),
        .cli => return error.TestUnexpectedResult,
    }
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

    try std.testing.expect(invocation.hasOption("force"));
    try std.testing.expect(invocation.hasOption("output"));
    try std.testing.expect(!invocation.hasOption("missing"));

    try std.testing.expect(invocation.optionValue("force") == null);
    try std.testing.expectEqualStrings("result.txt", invocation.optionValue("output").?);
    try std.testing.expect(invocation.optionValue("missing") == null);
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
