const std = @import("std");
const c = @import("c.zig");
const sys = @import("sys.zig");
const ptrace = @import("ptrace.zig");

fn usage(program_name: [*c]const u8) void {
    std.debug.print("Usage: {s} <command>\n", .{program_name});
}

const Tracee = struct {
    fn init(pid: c.pid_t) !Tracee {
        // Set options for ptrace. The purpose of PTRACE_O_TRACESYSGOOD is to
        // distinguish between syscall stops and signal delivery stop. The
        // purpose of PTRACE_O_TRACEFORK, PTRACE_O_TRACEVFORK and
        // PTRACE_O_TRACECLONE is to automatically start tracing any newly
        // created child processes. Technically, we will also receive
        // additional ptrace events on call to fork(), vfork() and clone() but
        // we are not interested in that.
        var options: usize = 0;
        options |= c.PTRACE_O_TRACESYSGOOD;
        options |= c.PTRACE_O_TRACEFORK;
        options |= c.PTRACE_O_TRACEVFORK;
        options |= c.PTRACE_O_TRACECLONE;
        try ptrace.setoptions(pid, options);
        return .{};
    }

    fn on_syscall_entry(self: *Tracee, pid: c.pid_t, nr: usize, args: [6]usize) void {
        _ = self;
        std.debug.print("Process {d}: syscall entry: nr = {d}, args = {any}\n", .{ pid, nr, args });
    }

    fn on_syscall_exit(self: *Tracee, pid: c.pid_t, rval: isize, is_error: bool) void {
        _ = self;
        std.debug.print("Process {d}: syscall exit: rval = {d}, is_error = {}\n", .{ pid, rval, is_error });
    }
};

const Tracees = std.AutoHashMap(c.pid_t, Tracee);

const Tracer = struct {
    tracees: Tracees,

    fn init(allocator: std.mem.Allocator) !Tracer {
        const tracees = Tracees.init(allocator);
        return .{ .tracees = tracees };
    }

    fn deinit(self: *Tracer) void {
        self.tracees.deinit();
    }

    fn get_tracee(self: *Tracer, pid: c.pid_t) !*Tracee {
        const entry = try self.tracees.getOrPut(pid);
        if (!entry.found_existing) {
            entry.value_ptr.* = try Tracee.init(pid);
        }
        return entry.value_ptr;
    }

    fn run(self: *Tracer, command: [][*:0]u8) !void {
        _ = try ptrace.spawnvp(command[0], command.ptr);

        var status: c_int = undefined;
        while (try sys.wait(&status)) |pid| {
            if (c.WIFEXITED(status)) {
                _ = self.tracees.remove(pid);
                std.debug.print("Process {d} exited with status code {d}.\n", .{ pid, c.WEXITSTATUS(status) });
                continue;
            }

            if (c.WIFSIGNALED(status)) {
                _ = self.tracees.remove(pid);
                std.debug.print("Process {d} terminated by signal SIG{s}.\n", .{ pid, c.sigabbrev_np(c.WTERMSIG(status)) });
                continue;
            }

            if (c.WIFSTOPPED(status)) {
                const tracee = try self.get_tracee(pid);

                if (c.WSTOPSIG(status) == c.SIGTRAP | 0x80) {
                    const info = try ptrace.get_syscall_info(pid);
                    switch (info.op) {
                        c.PTRACE_SYSCALL_INFO_ENTRY => tracee.on_syscall_entry(pid, info.unnamed_0.entry.nr, info.unnamed_0.entry.args),
                        c.PTRACE_SYSCALL_INFO_EXIT => tracee.on_syscall_exit(pid, info.unnamed_0.exit.rval, info.unnamed_0.exit.is_error != 0),
                        else => {},
                    }
                }

                try ptrace.syscall(pid);
            }
        }
    }

    fn on_syscall_entry(self: *Tracer, pid: c.pid_t, nr: usize, args: [6]usize) void {
        _ = self;
        std.debug.print("Process {d}: syscall entry: nr = {d}, args = {any}\n", .{ pid, nr, args });
    }

    fn on_syscall_exit(self: *Tracer, pid: c.pid_t, rval: isize, is_error: bool) void {
        _ = self;
        std.debug.print("Process {d}: syscall exit: rval = {d}, is_error = {}\n", .{ pid, rval, is_error });
    }
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const args = std.os.argv;
    const program_name = args[0];
    const command = args[1..];
    if (command.len == 0) {
        return usage(program_name);
    }

    var tracer = try Tracer.init(allocator);
    defer tracer.deinit();
    try tracer.run(command);
}
