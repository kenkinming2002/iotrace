//! This module provide thin wrapper over different operation of ptrace(2),
//! which will also report error via call to perror(3) and propagate the error
//! up via zig error union.

const std = @import("std");
const c = @import("c.zig");
const sys = @import("sys.zig");

inline fn ptrace(op: c.enum___ptrace_request, pid: c.pid_t, address: ?*anyopaque, data: ?*anyopaque) c_long {
    return c.ptrace(op, pid, address, data);
}

pub fn traceme() !void {
    if (ptrace(c.PTRACE_TRACEME, -1, null, null) == -1) {
        c.perror("ptrace()");
        return error.ptrace;
    }
}

pub fn setoptions(pid: c.pid_t, options: usize) !void {
    if (ptrace(c.PTRACE_SETOPTIONS, pid, null, @ptrFromInt(options)) == -1) {
        c.perror("ptrace()");
        return error.ptrace;
    }
}

pub fn syscall(pid: c.pid_t) !void {
    if (ptrace(c.PTRACE_SYSCALL, pid, null, null) == -1) {
        c.perror("ptrace");
        return error.ptrace;
    }
}

pub fn get_syscall_info(pid: c.pid_t) !c.struct___ptrace_syscall_info {
    var info: c.struct___ptrace_syscall_info = undefined;
    if (ptrace(c.PTRACE_GET_SYSCALL_INFO, pid, @ptrFromInt(@sizeOf(@TypeOf(info))), &info) == -1) {
        c.perror("ptrace()");
        return error.ptrace;
    }
    return info;
}

pub fn spawnvp(file: [*c]const u8, argv: [*c]const [*c]u8) !c.pid_t {
    switch (c.fork()) {
        0 => {
            traceme() catch c.exit(1);
            sys.execvp(file, argv) catch c.exit(1);
            unreachable;
        },
        -1 => return error.fork,
        else => |pid| return pid,
    }
}

pub fn trace_syscalls(allocator: std.mem.Allocator, context: anytype, comptime callback: fn (@TypeOf(context), pid: c.pid_t, nr: usize, args: [6]usize, rval: isize, is_error: u8) anyerror!void) !void {
    const State = struct { inner: ?struct { nr: usize, args: [6]usize } };
    const States = std.AutoHashMap(c.pid_t, State);

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
                try setoptions(pid, options);
            }

            const state = entry.value_ptr;

            if (c.WSTOPSIG(status) == c.SIGTRAP | 0x80) {
                const info = try get_syscall_info(pid);
                switch (info.op) {
                    c.PTRACE_SYSCALL_INFO_ENTRY => {
                        const entry_info = info.unnamed_0.entry;
                        state.inner = .{ .nr = entry_info.nr, .args = entry_info.args };
                    },
                    c.PTRACE_SYSCALL_INFO_EXIT => {
                        const exit_info = info.unnamed_0.exit;
                        try callback(context, pid, state.inner.?.nr, state.inner.?.args, exit_info.rval, exit_info.is_error);
                    },
                    else => {},
                }
            }

            try syscall(pid);
        }
    }
}
