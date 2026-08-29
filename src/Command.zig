const Command = @This();

name: []const u8,
description: ?[]const u8 = null,

aliases: []const []const u8 = &.{},

arguments: []const Argument = &.{},
options: []const Option = &.{},
commands: []const Command = &.{},


pub const Argument = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    required: bool = true,
};

pub const Option = struct {
    long: ?[]const u8 = null,
    short: ?u8 = null,

    kind: Kind = .flag,
    default: ?[]const u8 = null,
    persistent: bool = false,

    description: ?[]const u8 = null,

    pub const Kind = enum {
        flag,
        value,
    };
};
