const c = @import("c.zig");

const Self = @This();

pub const Type = enum(u8) {
    Read,
    Write,
    Send,
    Recv,
};

pid: c.pid_t align(1),
fd: i32 align(1),
type: Type align(1),
count: usize align(1),
timestamp: u64 align(1) = undefined,

pub fn parse(pid: c.pid_t, nr: usize, args: [6]usize, rval: isize, is_error: u8) ?Self {
    if (is_error != 0)
        return null;

    return switch (nr) {
        c.SYS_read => .{
            .pid = pid,
            .fd = @intCast(args[0]),
            .type = .Read,
            .count = @intCast(rval),
        },
        c.SYS_write => .{
            .pid = pid,
            .fd = @intCast(args[0]),
            .type = .Write,
            .count = @intCast(rval),
        },
        c.SYS_sendto => .{
            .pid = pid,
            .fd = @intCast(args[0]),
            .type = .Send,
            .count = @intCast(rval),
        },
        c.SYS_recvfrom => .{
            .pid = pid,
            .fd = @intCast(args[0]),
            .type = .Recv,
            .count = @intCast(rval),
        },
        else => null,
    };
}
