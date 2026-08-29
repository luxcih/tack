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
};

pub const Option = struct {
    long: ?[]const u8 = null,
    short: ?u8 = null,
    description: ?[]const u8 = null,
};
