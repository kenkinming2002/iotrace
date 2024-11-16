const std = @import("std");
const c = @import("c.zig");
const ptrace = @import("ptrace.zig");
const Packet = @import("Packet.zig");

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

pub fn record(log_file_path: []const u8, command: [][*]u8) !void {
    const allocator = std.heap.c_allocator;

    var context = try Context.init(log_file_path);
    defer context.deinit();

    _ = try ptrace.spawnvp(command[0], command.ptr);
    try ptrace.trace_syscalls(allocator, &context, Context.callback);
}
