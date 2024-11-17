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

pub const Child = struct {
    pid: c.pid_t,
    stdin: std.fs.File,

    pub fn wait(self: *Child) !void {
        if (c.waitpid(self.pid, null, 0) == -1) {
            c.perror("waitpid()");
            return error.waitpid;
        }
    }

    pub fn deinit(self: *Child) void {
        self.stdin.close();
    }
};

/// Spawn a child process, returning its stdin.
///
/// The arguments have the same semantic as execvp(3).
///
/// This is because the version found in std.process.Child is broken. If there
/// were to be an error in the call to exec(3) function (for example because
/// the program we attempt to execute is not present), it would be reported
/// using a pipe. The problem is that we can only retrive the error by calling
/// std.process.Child.wait, which we do not want to do because we are about to
/// write to the stdin of the spawned child process. We do not want to wait for
/// the process to terminate.
pub fn spawnvp_stdin(file: [*c]const u8, argv: [*c]const [*c]u8) !Child {
    // Setup pipes.
    //
    // We are creating a scope here explicitly because we close some of the
    // pipes manually later on, and we no longer want errdefer to take effect.
    var error_pipes: [2]c_int = undefined;
    var stdin_pipes: [2]c_int = undefined;
    {
        if (c.pipe(&error_pipes) == -1) {
            c.perror("pipe()");
            return error.pipe;
        }

        errdefer _ = c.close(error_pipes[0]);
        errdefer _ = c.close(error_pipes[1]);

        if (c.pipe(&stdin_pipes) == -1) {
            c.perror("pipe()");
            return error.pipe;
        }

        errdefer _ = c.close(stdin_pipes[0]);
        errdefer _ = c.close(stdin_pipes[1]);
    }

    switch (c.fork()) {
        -1 => return error.fork,
        0 => {
            // Setup error pipes.
            _ = c.close(error_pipes[0]);
            _ = c.fcntl(error_pipes[1], c.F_SETFD, c.fcntl(error_pipes[1], c.F_GETFD) | c.FD_CLOEXEC);

            // Setup stdin pipes.
            _ = c.dup2(stdin_pipes[0], c.STDIN_FILENO);
            _ = c.close(stdin_pipes[0]);
            _ = c.close(stdin_pipes[1]);

            // Call exec(3) and optionally report error.
            if (c.execvp(file, argv) == -1) {
                const errno: i32 = std.c._errno().*;
                _ = c.write(error_pipes[1], &errno, @sizeOf(@TypeOf(errno)));
                c.exit(1);
            }

            unreachable;
        },
        else => |pid| {
            // Clean up error pipe.
            defer _ = c.close(error_pipes[0]);
            _ = c.close(error_pipes[1]);

            // Clean up stdin pipe.
            errdefer _ = c.close(stdin_pipes[1]);
            _ = c.close(stdin_pipes[0]);

            // Try to read errno.
            var errno: i32 = undefined;
            if (c.read(error_pipes[0], &errno, @sizeOf(@TypeOf(errno))) == @sizeOf(@TypeOf(errno))) {
                std.c._errno().* = errno;
                c.perror("execvp()");
                return error.execvp;
            }

            return .{
                .pid = pid,
                .stdin = std.fs.File{ .handle = stdin_pipes[1] },
            };
        },
    }
}
