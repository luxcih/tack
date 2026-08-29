# Tack

A composable command-line interface library for Zig.

Tack separates command-line parsing from application behavior, giving programs explicit control over how an invocation is handled.

## Features

- Commands and nested subcommands
- Positional arguments
- Flags and value options
- Short and long options
- Command aliases
- Persistent options
- Default option values
- Actions and final actions
- Optional built-in help

## Installation

Add Tack to your project with `zig fetch`:

```sh
zig fetch --save https://github.com/luxcih/tack/archive/refs/tags/v0.1.0.tar.gz
```

Then import its module from your `build.zig`:

```zig
const tack_dep = b.dependency("tack", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("tack", tack_dep.module("tack"));
```

See the Zig build system documentation for more information about package dependencies.

## Quick start

```zig
const std = @import("std");
const tack = @import("tack");

const cli = tack.CLI{
    .name = "hello",
    .description = "A small Tack example.",
    .arguments = &.{
        .{
            .name = "name",
            .description = "Who to greet.",
        },
    },
    .options = &.{
        tack.builtin.help.option,
    },
    .action = tack.builtin.help.action,
    .final_action = run,
};

fn run(invocation: *const tack.Invocation) !void {
    const name = invocation.argument("name").?;
    std.debug.print("Hello, {s}!\\n", .{name});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    try cli.run(gpa.allocator(), std.os.argv[1..]);
}
```

## Built-in help

Tack does not automatically add behavior such as help handling. Instead, built-ins are explicitly composed into a CLI.

```zig
.options = &.{
    tack.builtin.help.option,
},
.commands = &.{
    tack.builtin.help.command,
},
.action = tack.builtin.help.action,
```

This provides:

```text
hello --help
hello -h
hello help
hello help <command>
```

Applications can replace or omit these built-ins and implement their own behavior.

## Status

Tack is currently pre-1.0 software. Its public API may change as it is tested through real projects.

## License

Tack is licensed under the MIT License.
