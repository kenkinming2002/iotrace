const std = @import("std");
const c = @import("c.zig");
const sys = @import("sys.zig");
const ptrace = @import("ptrace.zig");

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
    log_file: std.fs.File,

    fn init(log_file_path: []const u8) !Context {
        const timer = try std.time.Timer.start();
        const log_file = try std.fs.cwd().createFile(log_file_path, .{});
        return .{ .timer = timer, .log_file = log_file };
    }

    fn deinit(self: *Context) void {
        self.log_file.close();
    }

    fn callback(self: *Context, pid: c.pid_t, nr: usize, args: [6]usize, rval: isize, is_error: u8) anyerror!void {
        var packet = Packet.parse(pid, nr, args, rval, is_error) orelse return;
        packet.timestamp = self.timer.read();
        try self.log_file.writeAll(std.mem.asBytes(&packet));
    }
};

fn record(log_file_path: []const u8, command: [][*]u8) !void {
    const allocator = std.heap.c_allocator;

    var context = try Context.init(log_file_path);
    defer context.deinit();

    _ = try ptrace.spawnvp(command[0], command.ptr);
    try ptrace.trace_syscalls(allocator, &context, Context.callback);
}

fn report(log_file_path: []const u8) !void {
    _ = log_file_path;
}

fn usage(program_name: [*c]const u8) void {
    std.debug.print("Usage: {s} record|report ...\n", .{program_name});
    std.debug.print("       {s} record <file> <command>\n", .{program_name});
    std.debug.print("       {s} report <file>\n", .{program_name});
}

pub fn main() !void {
    const argv = std.os.argv;
    const program_name = argv[0];
    if (argv.len < 2) {
        return usage(program_name);
    }

    const subcommand = std.mem.span(argv[1]);
    if (std.mem.eql(u8, subcommand, "record")) {
        if (argv.len < 3) {
            std.debug.print("Error: Missing argument <file>\n", .{});
            return usage(program_name);
        }

        if (argv.len < 4) {
            std.debug.print("Error: Missing argument <command>\n", .{});
            return usage(program_name);
        }

        const log_file_path = std.mem.span(argv[2]);
        const command = argv[3..];
        return record(log_file_path, command);
    }

    if (std.mem.eql(u8, subcommand, "report")) {
        if (argv.len != 3) {
            std.debug.print("Error: Missing argument <file>\n", .{});
            return usage(program_name);
        }

        const log_file_path = std.mem.span(argv[2]);
        return report(log_file_path);
    }

    return usage(program_name);
}
