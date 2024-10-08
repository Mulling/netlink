const std = @import("std");

pub const GENL_ID_CTRL: u8 = 0x10;

pub const Header = extern struct {
    cmd: u8,
    version: u8 = 2,
    reserved: u16 = undefined,

    const Self = @This();

    pub const CTRL_CMD_GETFAMILY: u8 = 0x03;

    pub fn init() Header {
        return std.mem.zeroes(Self);
    }
};
