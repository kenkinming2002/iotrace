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
