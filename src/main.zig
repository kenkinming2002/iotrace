const std = @import("std");
const c = @import("c.zig");
const sys = @import("sys.zig");
const ptrace = @import("ptrace.zig");

fn usage(program_name: [*c]const u8) void {
    std.debug.print("Usage: {s} <output-file> <command>\n", .{program_name});
}

const PacketType = enum(u8) {
    Read,
    Write,
};

const Packet = extern struct {
    pid: c.pid_t align(1),
    fd: i32 align(1),
    type: PacketType align(1),
    count: usize align(1),
    timestamp: u64 align(1) = undefined,

    fn parse(pid: c.pid_t, nr: usize, args: [6]usize, rval: isize, is_error: u8) ?Packet {
        if (is_error != 0)
            return null;

        return switch (nr) {
            c.SYS_read => .{
                .pid = pid,
                .fd = @intCast(args[0]),
                .type = .Write,
                .count = @intCast(rval),
            },
            c.SYS_write => .{
                .pid = pid,
                .fd = @intCast(args[0]),
                .type = .Write,
                .count = @intCast(rval),
            },
            else => null,
        };
    }
};

const Context = struct {
    timer: std.time.Timer,
    output_file: std.fs.File,

    fn init(output_file_path: []const u8) !Context {
        const timer = try std.time.Timer.start();
        const output_file = try std.fs.cwd().createFile(output_file_path, .{});
        return .{ .timer = timer, .output_file = output_file };
    }

    fn deinit(self: *Context) void {
        self.output_file.close();
    }

    fn callback(self: *Context, pid: c.pid_t, nr: usize, args: [6]usize, rval: isize, is_error: u8) anyerror!void {
        var packet = Packet.parse(pid, nr, args, rval, is_error) orelse return;
        packet.timestamp = self.timer.read();
        try self.output_file.writeAll(std.mem.asBytes(&packet));
    }
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const argv = std.os.argv;
    const program_name = argv[0];
    if (argv.len < 3) {
        return usage(program_name);
    }

    const output_file_path = argv[1];
    const command = argv[2..];

    var context = try Context.init(std.mem.span(output_file_path));
    defer context.deinit();

    _ = try ptrace.spawnvp(command[0], command.ptr);
    try ptrace.trace_syscalls(allocator, &context, Context.callback);
}
