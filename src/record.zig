const std = @import("std");
const c = @import("c.zig");
const sys = @import("sys.zig");
const ptrace = @import("ptrace.zig");
const Packet = @import("Packet.zig");

pub fn record(log_file_path: []const u8, command: [][*]u8) !void {
    const State = struct { inner: ?struct { nr: usize, args: [6]usize } };
    const States = std.AutoHashMap(c.pid_t, State);

    const allocator = std.heap.c_allocator;

    const log_file = try std.fs.cwd().createFile(log_file_path, .{});
    defer log_file.close();

    var timer = try std.time.Timer.start();

    _ = try ptrace.spawnvp(command[0], command.ptr);

    var states = States.init(allocator);
    defer states.deinit();

    var status: c_int = undefined;
    while (try sys.wait(&status)) |pid| {
        if (c.WIFEXITED(status)) {
            _ = states.remove(pid);
            continue;
        }

        if (c.WIFSIGNALED(status)) {
            _ = states.remove(pid);
            continue;
        }

        if (c.WIFSTOPPED(status)) {
            const entry = try states.getOrPut(pid);
            if (!entry.found_existing) {
                entry.value_ptr.inner = null;

                var options: usize = 0;
                options |= c.PTRACE_O_TRACESYSGOOD;
                options |= c.PTRACE_O_TRACEFORK;
                options |= c.PTRACE_O_TRACEVFORK;
                options |= c.PTRACE_O_TRACECLONE;
                try ptrace.setoptions(pid, options);
            }

            const state = entry.value_ptr;
            if (c.WSTOPSIG(status) == c.SIGTRAP | 0x80) {
                const info = try ptrace.get_syscall_info(pid);
                switch (info.op) {
                    c.PTRACE_SYSCALL_INFO_ENTRY => {
                        const entry_info = info.unnamed_0.entry;
                        state.inner = .{ .nr = entry_info.nr, .args = entry_info.args };
                    },
                    c.PTRACE_SYSCALL_INFO_EXIT => out: {
                        const exit_info = info.unnamed_0.exit;
                        var packet = Packet.parse(pid, state.inner.?.nr, state.inner.?.args, exit_info.rval, exit_info.is_error) orelse break :out;
                        packet.timestamp = timer.read();
                        try log_file.writeAll(std.mem.asBytes(&packet));
                    },
                    else => {},
                }
            }

            try ptrace.syscall(pid);
        }
    }
}
