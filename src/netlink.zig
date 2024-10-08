const std = @import("std");

pub const generic = @import("generic.zig");

const NL = std.os.linux.NETLINK;
const SO = std.os.linux.SO;
const SOCK = std.os.linux.SOCK;
const SOL = std.os.linux.SOL;
const AF = std.os.linux.AF;

inline fn align_to(comptime to: u32, comptime n: u32) comptime_int {
    return (n + (to - 1)) & ~(to - 1);
}

fn sys(comptime T: type, ret: usize) !T {
    const errno = std.posix.errno(ret);

    switch (errno) {
        .SUCCESS => {
            return switch (T) {
                u32 => @intCast(ret),
                i32 => @truncate(@as(isize, @intCast(ret))),
                void => {},
                else => @panic("Type not supported."),
            };
        },
        else => {
            @panic("errno");
        },
    }
}

pub const SockAddr = extern struct {
    family: u16 = AF.NETLINK,
    pad: u16 = 0,
    pid: u32 = 0,
    groups: u32 = 0,
};

pub const Sock = struct {
    socket: i32 = 0,
    sockaddr: SockAddr,
    protocol: i32,

    buf: [16384]u8,

    const Self = @This();

    pub fn init(protocol: i32) !Sock {
        const socket = try sys(i32, std.os.linux.socket(AF.NETLINK, SOCK.RAW | SOCK.CLOEXEC, NL.GENERIC));

        const buf_len: u32 = 16384;

        try sys(
            void,
            std.os.linux.setsockopt(socket, SOL.SOCKET, SO.SNDBUF, @ptrCast(&buf_len), @sizeOf(u32)),
        );

        try sys(
            void,
            std.os.linux.setsockopt(socket, SOL.SOCKET, SO.RCVBUF, @ptrCast(&buf_len), @sizeOf(u32)),
        );

        return .{
            .socket = socket,
            .sockaddr = .{},
            .protocol = protocol,
            .buf = std.mem.zeroes([16384]u8),
        };
    }

    pub fn bind(self: *Self, sockaddr: SockAddr) !void {
        self.sockaddr = sockaddr;

        var sockaddr_len: u32 = @sizeOf(SockAddr);

        try sys(void, std.os.linux.bind(self.socket, @ptrCast(&self.sockaddr), @sizeOf(SockAddr)));
        try sys(void, std.os.linux.getsockname(self.socket, @ptrCast(&self.sockaddr), &sockaddr_len));

        if (sockaddr_len != @sizeOf(SockAddr)) return error.wrong_address_len;
        if (self.sockaddr.family != AF.NETLINK) return error.wrong_address_family;
    }

    fn sendmsg(self: *const Self, payload: anytype) !void {
        var msghdr = std.mem.zeroes(std.os.linux.msghdr);

        var iovec = std.posix.iovec{
            .base = @constCast(@ptrCast(@alignCast(&payload))),
            .len = @sizeOf(@TypeOf(payload)),
        };

        var sockaddr: SockAddr = .{};

        msghdr.iov = @ptrCast(&iovec);
        msghdr.iovlen = 1;
        msghdr.name = @ptrCast(&sockaddr);
        msghdr.namelen = @sizeOf(SockAddr);

        const sent = try sys(u32, std.os.linux.sendmsg(self.socket, @ptrCast(&msghdr), 0));

        std.debug.assert(sent == @sizeOf(@TypeOf(payload)));
    }

    fn recevmsg(self: *const Self, base: []u8) !void {
        var msghdr = std.mem.zeroes(std.os.linux.msghdr);

        @memset(base, 0);

        base[0] = 0;

        var iovec = std.posix.iovec{
            .base = base.ptr,
            .len = base.len,
        };

        var sockaddr: SockAddr = .{};

        msghdr.iov = @ptrCast(&iovec);
        msghdr.iovlen = 1;
        msghdr.name = @ptrCast(&sockaddr);
        msghdr.namelen = @sizeOf(SockAddr);

        const recvd = try sys(u32, std.os.linux.recvmsg(self.socket, @ptrCast(@alignCast(&msghdr)), std.os.linux.MSG.CMSG_CLOEXEC));

        const group_id = std.mem.readInt(u32, base[80..84], .little);

        std.debug.print("len = {}, group_id = {}", .{ recvd, group_id });
    }

    pub fn get_group_id(self: *Self, comptime group_name: anytype) !u32 {
        try self.sendmsg(Payload(group_name){});
        try self.recevmsg(&self.buf);
        return 0;
    }
};

pub const Header = extern struct {
    len: u32,
    kind: u16,
    flags: u16,
    seq: u32 = undefined,
    pid: u32 = undefined,

    const Self = @This();

    fn init() Header {
        return std.mem.zeroes(Self);
    }
};

const RouteInfromationAttribute = extern struct {
    pub const CTRL_ATTR_FAMILY_NAME: u16 = 0x02;

    len: u16,
    kind: u16,

    const Self = @This();

    fn init() RouteInfromationAttribute {
        return std.mem.zeroes(Self);
    }
};

fn Payload(comptime D: anytype) type {
    const len = D.len;
    const pad = align_to(4, len);

    const size = @sizeOf(Header) + @sizeOf(generic.Header) + @sizeOf(RouteInfromationAttribute) + pad;

    comptime var data: [len + 1]u8 = std.mem.zeroes([len + 1]u8);

    @memcpy(data[0..len], D.*[0..len]);

    return extern struct {
        header: Header = .{
            .len = size,
            .kind = generic.GENL_ID_CTRL,
            .flags = std.os.linux.NLM_F_ACK | std.os.linux.NLM_F_REQUEST,
        },
        generic_header: generic.Header = .{
            .cmd = generic.Header.CTRL_CMD_GETFAMILY,
        },
        attr: RouteInfromationAttribute = .{
            .len = len + 1 + @sizeOf(RouteInfromationAttribute),
            .kind = RouteInfromationAttribute.CTRL_ATTR_FAMILY_NAME,
        },
        data: [len + 1]u8 = data,
    };
}
