const std = @import("std");

const nl = @import("netlink");

test "generic netlink socket" {
    var socket = try nl.Sock.init(std.os.linux.NETLINK.GENERIC);

    try socket.bind(.{});

    _ = try socket.get_group_id("acpi_event");
}
