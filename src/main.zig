const std = @import("std");
const ptrace = @import("ptrace.zig");

const record = @import("record.zig").record;
const report = @import("report.zig").report;

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
