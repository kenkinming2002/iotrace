const std = @import("std");
const Packet = @import("Packet.zig");

pub fn report(log_file_path: []const u8) !void {
    var log_file = try std.fs.cwd().openFile(log_file_path, .{});
    defer log_file.close();

    var bytes_read: usize = 0;
    var bytes_written: usize = 0;

    var packet: Packet = undefined;
    while (try log_file.readAll(std.mem.asBytes(&packet)) == @sizeOf(@TypeOf(packet))) {
        if (packet.fd != 1)
            continue;

        switch (packet.type) {
            .Read => bytes_read += packet.count,
            .Write => bytes_written += packet.count,
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Bytes read: {d}\n", .{bytes_read});
    try stdout.print("Bytes written: {d}\n", .{bytes_written});
}
