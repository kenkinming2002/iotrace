//! This module provide thin wrapper over posix function, which will report
//! error via call to perror(3) and propagate the error up via zig error union.

const std = @import("std");
const c = @import("c.zig");

pub fn execvp(__file: [*c]const u8, __argv: [*c]const [*c]u8) !void {
    if (c.execvp(__file, __argv) == -1) {
        c.perror("execvp()");
        return error.execvp;
    }
    unreachable;
}

pub fn wait(status: *c_int) !?c.pid_t {
    const pid = c.wait(status);
    if (pid == -1) {
        if (std.c._errno().* == c.ECHILD) {
            return null;
        }
        c.perror("wait");
        return error.wait;
    }
    return pid;
}
